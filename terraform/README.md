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
     -var='api_token_secret_version=1'
   ```

The runtime service account receives `roles/secretmanager.secretAccessor` on the named secret and `roles/storage.objectViewer` on the file bucket. Cloud Run injects the secret as `API_TOKEN`. Since public invocation is disabled, callers also need a Cloud Run IAM identity token in addition to the application API key. A production customer endpoint should use a load balancer, restrict Cloud Run ingress to that load balancer, and replace the shared exercise key with customer-scoped OIDC/JWT authorization.

Upload an object to `customers/{customer_id}/{file_id}` in the bucket output by Terraform. Then call the service URL with `X-API-Key` and a valid Cloud Run IAM identity token.

## Security and operations notes

- `allow_unauthenticated=true` is only for the Nginx demo. Use `false` for the Python deployment.
- The sample defaults to the `latest` Secret Manager version. Pin an explicit version for a production environment, and redeploy deliberately when rotating an environment-variable secret.
- Tune concurrency and instance bounds after load testing. Ensure Cloud Run, Artifact Registry, and Cloud Storage quotas support the target traffic.
- Bucket deletion is protected by `force_destroy=false`; empty it deliberately before destroying the stack.
- Do not commit Terraform state, credentials, or local `terraform.tfvars`.

Step: 1
After Deploying Terraform 

Outputs:
artifact_registry_repository = "europe-west2-docker.pkg.dev/assessment-512510/file-service"
runtime_service_account = "file-service-runtime@assessment-512510.iam.gserviceaccount.com"
service_url = "https://customer-file-service-y3kolzbnlq-nw.a.run.app"
storage_bucket = "assessment-512510-customer-files"

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
