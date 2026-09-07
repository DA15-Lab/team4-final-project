import os

from dotenv import load_dotenv
from sqlalchemy import create_engine


def get_engine():
    load_dotenv()

    return create_engine(
        f"mysql+pymysql://"
        f"{os.getenv('DB_USER')}:{os.getenv('DB_PASSWORD')}"
        f"@{os.getenv('DB_HOST')}:{os.getenv('DB_PORT')}"
        f"/{os.getenv('DB_NAME')}"
    )