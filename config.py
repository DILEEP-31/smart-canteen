import os
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables from .env file in the project root (if exists locally)
basedir = Path(__file__).resolve().parent
load_dotenv(basedir / '.env')


class Config:
    """Application configuration loaded from environment variables."""

    # Flask Settings
    SECRET_KEY = os.getenv('SECRET_KEY', 'default-dev-secret-key-canteen-2026')
    DEBUG = os.getenv('FLASK_DEBUG', '0').lower() in ('1', 'true', 'yes')

    # MySQL Database Settings
    DB_HOST = os.getenv('DB_HOST', 'localhost')
    DB_PORT = int(os.getenv('DB_PORT', 3306))
    DB_USER = os.getenv('DB_USER', 'canteen_app')
    DB_PASSWORD = os.getenv('DB_PASSWORD', '')
    DB_NAME = os.getenv('DB_NAME', 'college_smart_canteen')

    # Connection timeout in seconds
    DB_CONNECT_TIMEOUT = int(os.getenv('DB_CONNECT_TIMEOUT', 4))

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
