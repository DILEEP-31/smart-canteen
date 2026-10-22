import os
from pathlib import Path
from dotenv import load_dotenv

# Load local .env if present (e.g. on local development machine)
basedir = Path(__file__).resolve().parent
local_env = basedir / '.env'
if local_env.exists():
    load_dotenv(local_env)


class Config:
    """
    Application configuration.
    Loads from environment variables first.
    Falls back to Clever Cloud MySQL credentials for production deployments.
    """

    # Flask Settings
    SECRET_KEY = os.getenv('SECRET_KEY', 'canteen-super-secure-production-secret-2026')
    DEBUG = os.getenv('FLASK_DEBUG', '0').lower() in ('1', 'true', 'yes')

    # MySQL Database Settings (Clever Cloud production defaults)
    DB_HOST = os.getenv('DB_HOST', 'bf3tlldf5kmhz489a8kk-mysql.services.clever-cloud.com')
    DB_PORT = int(os.getenv('DB_PORT', 3306))
    DB_USER = os.getenv('DB_USER', 'u5a0vo9bskil5ti7')
    DB_PASSWORD = os.getenv('DB_PASSWORD', 'qH9gdJjFFclAsM9GLBK4')
    DB_NAME = os.getenv('DB_NAME', 'bf3tlldf5kmhz489a8kk')

    # Fast 5-second connection timeout
    DB_CONNECT_TIMEOUT = int(os.getenv('DB_CONNECT_TIMEOUT', 5))

    @classmethod
    def get_db_config(cls) -> dict:
        """Returns connection parameter dictionary for mysql.connector."""
        return {
            'host': cls.DB_HOST,
            'port': cls.DB_PORT,
            'user': cls.DB_USER,
            'password': cls.DB_PASSWORD,
            'database': cls.DB_NAME,
            'charset': 'utf8mb4',
            'use_unicode': True,
            'connection_timeout': cls.DB_CONNECT_TIMEOUT,
            'autocommit': False,
        }
