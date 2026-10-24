# Terraform infrastructure

This starter creates the private Cloud Storage bucket, dedicated Cloud Run runtime service account, read-only bucket binding, Artifact Registry repository, and Cloud Run v2 service. The default image is the public Nginx welcome page. For the Python rollout, Terraform can reference a Secret Manager token without putting the token value in Terraform state.

## Prerequisites

- Terraform 1.5+
- `gcloud` with permission to enable APIs and create the listed resources
- Docker for building the Python service image

## Stage 2: Nginx placeholder

From the repository root:

```sh
gcloud auth application-default login
cd terraform
terraform init
terraform fmt -check
terraform validate
terraform plan -var='project_id=YOUR_PROJECT_ID' -var='allow_unauthenticated=true'
terraform apply -var='project_id=YOUR_PROJECT_ID' -var='allow_unauthenticated=true'
```

The placeholder uses port 80, one warm instance, a 100-instance cap, and concurrency 80. Obtain its URL with `terraform output -raw service_url`. The public invoker is intended only for this temporary Nginx stage.

## Stage 3: Python service

1. Create a Secret Manager secret and add a version outside Terraform. The secret value is never written to Terraform state:

   ```sh
   gcloud secrets create file-api-token --replication-policy=automatic --project=YOUR_PROJECT_ID
   read -rs "API_TOKEN?API token: "
   printf '\n'
   printf '%s' "$API_TOKEN" | gcloud secrets versions add file-api-token --data-file=- --project=YOUR_PROJECT_ID
   unset API_TOKEN
   ```

2. Build and push the application image to the Terraform-created Artifact Registry repository:

   ```sh
   cd ..
   PROJECT_ID="YOUR_PROJECT_ID"
   REGION="europe-west2"
   IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/file-service/file-service:v1"
   gcloud auth configure-docker "${REGION}-docker.pkg.dev"
   docker build -t "${IMAGE}" ./platform-file-service
   docker push "${IMAGE}"
   ```

3. Apply the Python configuration. Set the secret name, service image, port 8080, and disable public invocation:

   ```sh
   PROJECT_ID="YOUR_PROJECT_ID"
   REGION="europe-west2"
   cd terraform
   terraform apply \
     -var="project_id=${PROJECT_ID}" \
     -var="container_image=${REGION}-docker.pkg.dev/${PROJECT_ID}/file-service/file-service:v1" \
     -var='container_port=8080' \
     -var='allow_unauthenticated=false' \
     -var='api_token_secret_name=file-api-token' \
      -var='api_token_secret_version=1' \
      -var='api_token_customer_id=demo-customer'
   ```

The runtime service account receives `roles/secretmanager.secretAccessor` on the named secret and `roles/storage.objectViewer` on the file bucket. Cloud Run injects the secret as `API_TOKEN` and sets `API_TOKEN_CUSTOMER_ID`. The exercise token is scoped to that one customer ID; requests naming another customer receive HTTP 403 before the service contacts Cloud Storage. Since public invocation is disabled, callers also need a Cloud Run IAM identity token in addition to the application API key. A production customer endpoint should use a load balancer, restrict Cloud Run ingress to that load balancer, and replace the static exercise token with validated customer-scoped OIDC/JWT authorization.

## Optional global HTTPS load balancer and Cloud Armor demo

Terraform can also create a global external Application Load Balancer in front of Cloud Run, attach a Google-managed HTTPS certificate, redirect HTTP to HTTPS, and attach a Cloud Armor policy with SQL injection and XSS WAF rules. Load balancer request logging is enabled, including Cloud Armor decision details. The WAF rules are enforced at sensitivity 1; review the load balancer logs for false positives before increasing sensitivity or using this unchanged in production.

You need a domain name you control and permission to update its DNS. Choose a hostname such as `files.example.com`; replace it below with your real hostname. The domain is required for Google's managed certificate. Apply the same Python image configuration as above, and add `enable_external_https_lb=true` and `lb_domain`:

```sh
cd ~/Documents/Platform-Engineer-assessment/terraform
PROJECT_ID="assessment-512510"
DOMAIN="files.YOUR-DOMAIN"
IMAGE="europe-west2-docker.pkg.dev/${PROJECT_ID}/file-service/file-service:v2"

terraform plan \
  -var-file="terraform.tfvars.example" \
  -var="container_image=${IMAGE}" \
  -var='container_port=8080' \
  -var='allow_unauthenticated=false' \
  -var='api_token_secret_name=file-api-token' \
  -var='api_token_secret_version=1' \
  -var='api_token_customer_id=demo-customer' \
  -var='enable_external_https_lb=true' \
  -var="lb_domain=${DOMAIN}"
```

Review the plan: it should update Cloud Run ingress to `INGRESS_TRAFFIC_INTERNAL_LOAD_BALANCER` and create the load balancer, Cloud Armor policy, and certificate. When it looks right, rerun that command with `terraform apply` instead of `terraform plan`. The `run.app` URL will no longer accept external traffic directly; the Cloud Run invoker IAM binding is granted so the serverless NEG can reach the service, while restricted ingress forces external requests through the load balancer. The Python API still requires its `X-API-Key` and customer check.

After apply, get the reserved address:

```sh
terraform output -raw load_balancer_ip
```

At your DNS provider, create an **A record** for the exact `DOMAIN` hostname pointing to that IPv4 address. Wait for DNS to resolve and for the managed certificate to become active (this can take some time). Then test through `https://${DOMAIN}`. Cloud Armor WAF blocks requests matching its configured SQLi/XSS rules; the default policy allows other traffic through to application authentication. This is a demo WAF policy, not a substitute for tenant authorization or rate limiting.

The global forwarding rules, reserved address, and Cloud Armor can incur charges even at low traffic. Check current GCP pricing before leaving this demo deployed. Destroying Terraform resources will remove the load balancer and IP; do that only when you're finished with the demo.

### Temporary HTTP-only demo when you do not own a domain

You can still demonstrate the external load balancer and attached Cloud Armor policy without a hostname by enabling HTTP-only mode. This does **not** provide TLS: the `X-API-Key` and response travel unencrypted over the public internet. Use only the disposable exercise token and test file, never real customer data or production credentials.

```sh
cd ~/Documents/Platform-Engineer-assessment/terraform
terraform plan \
  -var-file="terraform.tfvars.example" \
  -var='container_image=europe-west2-docker.pkg.dev/assessment-512510/file-service/file-service:v2' \
  -var='container_port=8080' \
  -var='allow_unauthenticated=false' \
  -var='api_token_secret_name=file-api-token' \
  -var='api_token_secret_version=1' \
  -var='api_token_customer_id=demo-customer' \
  -var='enable_external_http_lb=true'
```

Review the plan, then rerun it with `terraform apply`. This restricts Cloud Run ingress to the load balancer and creates a static IP, serverless NEG, external HTTP load balancer, and Cloud Armor WAF policy. The load balancer needs public invocation permission to reach Cloud Run through the serverless NEG; restricted ingress prevents direct internet access to the `run.app` URL, and the Python service still checks the API key and configured customer ID.

Get the endpoint and test with the demo token:

```sh
terraform output -raw load_balancer_url
curl -i \
  -H 'X-API-Key: local-demo-token' \
  "$(terraform output -raw load_balancer_url)/v1/customers/demo-customer/files/welcome.txt"
```

This proves the request path through the HTTP load balancer and Cloud Armor, but does not demonstrate managed HTTPS or establish the throughput and latency SLOs. Destroy the temporary LB after the demo if you do not need it; the load balancer and Cloud Armor incur charges.

Upload an object to `customers/{customer_id}/{file_id}` in the bucket output by Terraform. Without the optional load balancer, call the Cloud Run service URL with both `X-API-Key` and a Cloud Run IAM identity token. With the HTTPS load balancer enabled, call `https://${DOMAIN}` with `X-API-Key`; with HTTP-only mode, use the `load_balancer_url` output and the demo token only.

### Redeploy the customer-scoped authorization improvement

The updated Python code binds the exercise token to `demo-customer`. Build and push it with a new image tag, then apply Terraform to create a Cloud Run revision with that image and the matching customer setting:

```sh
cd ~/Documents/Platform-Engineer-assessment
PROJECT_ID="assessment-512510"
REGION="europe-west2"
IMAGE="${REGION}-docker.pkg.dev/${PROJECT_ID}/file-service/file-service:v2"
docker build -t "${IMAGE}" ./platform-file-service
docker push "${IMAGE}"

cd terraform
terraform apply \
  -var-file="terraform.tfvars.example" \
  -var="container_image=${IMAGE}" \
  -var='container_port=8080' \
  -var='allow_unauthenticated=false' \
  -var='api_token_secret_name=file-api-token' \
  -var='api_token_secret_version=1' \
  -var='api_token_customer_id=demo-customer'
```

With the Cloud Run proxy running, the existing `demo-customer` request should continue to retrieve the file. A request for another customer using the same API key should return HTTP 403. This demonstrates a single-customer boundary for the exercise; production should derive authorization from a verified customer identity token.

```sh
curl -i \
  -H 'X-API-Key: local-demo-token' \
  http://localhost:8081/v1/customers/another-customer/files/welcome.txt
```

## Security and operations notes

- `allow_unauthenticated=true` is only for the Nginx demo. Use `false` for the Python deployment.
- The sample defaults to the `latest` Secret Manager version. Pin an explicit version for a production environment, and redeploy deliberately when rotating an environment-variable secret.
- Tune concurrency and instance bounds after load testing. Ensure Cloud Run, Artifact Registry, and Cloud Storage quotas support the target traffic.
- Bucket deletion is protected by `force_destroy=false`; empty it deliberately before destroying the stack.
- Do not commit Terraform state, credentials, or local `terraform.tfvars`.

## Core principles demonstrated

### Testability

Validate the configuration before applying it:

```sh
terraform fmt -check
terraform init -backend=false
terraform validate
terraform plan -var-file="terraform.tfvars.example"
```

`fmt` checks formatting, `validate` checks the Terraform configuration and provider schema, and `plan` previews the infrastructure changes for review. These checks do not prove that the deployed service meets its throughput, latency, or availability objectives. Those require representative load and failure testing.

### Simplicity

The module separates core resources (`main.tf`), optional edge resources (`load_balancer.tf`), input values (`variables.tf`), and outputs (`outputs.tf`). Load balancer resources are disabled by default so the basic Cloud Run and Storage deployment stays small.

### Security

The bucket enforces public access prevention and uniform bucket-level access. Cloud Run uses a dedicated runtime service account, with object-viewer access limited to the file bucket; its API token is referenced from Secret Manager instead of being written as a Terraform value. The Nginx demo can be public, but the Python deployment should set `allow_unauthenticated=false`. When the optional load balancer is enabled, Terraform restricts Cloud Run ingress to the load balancer and attaches the configured Cloud Armor WAF policy. The current application token is still an exercise credential, and the load balancer is optional rather than deployed by default.

### Observability

Cloud Run provides platform logs and metrics. The Python application writes structured request logs, and the optional load balancer backend enables request logging. This Terraform does not yet create custom Cloud Monitoring dashboards, SLO alert policies, or application tracing. Add those after choosing the service-level indicators and alert thresholds; do not treat the current scaling settings as evidence that an SLO is met.

Step: 1
After Deploying Terraform 

Outputs:
artifact_registry_repository = "europe-west2-docker.pkg.dev/assessment-512510/file-service"
runtime_service_account = "file-service-runtime@assessment-512510.iam.gserviceaccount.com"
service_url = "https://customer-file-service-y3kolzbnlq-nw.a.run.app"
storage_bucket = "assessment-512510-customer-files"

In the browser paste the service url 
Their is welcome to nginx page 

Step: 2
Run these from your repository root. cd /Users/manognasomula/Documents/Platform-Engineer-assessment
gcloud auth login
gcloud auth configure-docker europe-west2-docker.pkg.dev
docker build -t europe-west2-docker.pkg.dev/assessment-512510/file-service/file-service:v1 ./platform-file-service
docker push europe-west2-docker.pkg.dev/assessment-512510/file-service/file-service:v1

Step: 3
Created secrets 

gcloud secrets create file-api-token \
  --replication-policy=automatic \
  --project=assessment-512510

printf 'local-demo-token' | gcloud secrets versions add file-api-token \
  --data-file=- \
  --project=assessment-512510

I confirmed the exercise token in Secret Manager,by giving following command 
gcloud secrets create file-api-token \
  --replication-policy=automatic \
  --project=assessment-512510

Step: 4
cd ~/Documents/Platform-Engineer-assessment/terraform
terraform apply \
  -var-file="terraform.tfvars.example" \
  -var='container_image=europe-west2-docker.pkg.dev/assessment-512510/file-service/file-service:v1' \
  -var='container_port=8080' \
  -var='allow_unauthenticated=false' \
  -var='api_token_secret_name=file-api-token' \
  -var='api_token_secret_version=1'

  Outputs:

artifact_registry_repository = "europe-west2-docker.pkg.dev/assessment-512510/file-service"
runtime_service_account = "file-service-runtime@assessment-512510.iam.gserviceaccount.com"
service_url = "https://customer-file-service-y3kolzbnlq-nw.a.run.app"
storage_bucket = "assessment-512510-customer-files"


Created a welcome.txt in /temp directory and coped to s3 bucket

printf 'Hello from GCS\n' > /tmp/welcome.txt

gcloud storage cp /tmp/welcome.txt \
  gs://assessment-512510-customer-files/customers/demo-customer/welcome.txt

Output :
gcloud storage cp /tmp/welcome.txt \
>   gs://assessment-512510-customer-files/customers/demo-customer/welcome.txt
Copying file:///tmp/welcome.txt to gs://assessment-512510-customer-files/customers/demo-customer/welcome.txt
  Completed files 1/1 | 15.0B/15.0B 

One terminal I ran 

gcloud run services proxy customer-file-service \
  --region=europe-west2 \
  --project=assessment-512510 \
  --port=8081

Two terminal i ran 

curl -i \
  -H 'X-API-Key: local-demo-token' \
  http://localhost:8081/v1/customers/demo-customer/files/welcome.txt

OutPut :

HTTP/1.1 200 OK
Alt-Svc: h3=":443"; ma=2592000,h3-29=":443"; ma=2592000
Cache-Control: private, no-store
Content-Disposition: attachment; filename="welcome.txt"
Content-Length: 15
Content-Type: text/plain; charset=utf-8
Date: Fri, 23 Oct 2026 14:06:45 GMT
Server: Google Frontend
X-Cloud-Trace-Context: 996df3eac381a27dcb98882e94615d30;o=1
X-Content-Type-Options: nosniff

Hello from GCS

The customer-scoping change is now deployed and verified:
- demo-customer received HTTP 200 and the file contents.
- another-customer, using the same API key, received HTTP 403 Forbidden.
