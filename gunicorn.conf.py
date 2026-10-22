import os

# Gunicorn configuration file for Render and cloud deployments
# Automatically picked up by Gunicorn without needing CLI flags

port = os.environ.get("PORT", "10000")
bind = f"0.0.0.0:{port}"

workers = 2
threads = 4
timeout = 120
accesslog = "-"
errorlog = "-"
