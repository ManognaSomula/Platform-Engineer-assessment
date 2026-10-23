from dataclasses import dataclass
import os


@dataclass(frozen=True)
class Settings:
    api_token: str
    bucket: str
    log_level: str

    @classmethod
    def from_env(cls) -> "Settings":
        return cls(
            api_token=os.getenv("API_TOKEN", ""),
            bucket=os.getenv("GCS_BUCKET", ""),
            log_level=os.getenv("LOG_LEVEL", "INFO").upper(),
        )


settings = Settings.from_env()
