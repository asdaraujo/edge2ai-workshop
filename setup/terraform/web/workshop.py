"""
Workshop web application
"""
from app import app, db
from app.models import User, Cluster

@app.shell_context_processor
def make_shell_context():
    """Expose objects to Flask shell
    """
    return {'db': db, 'User': User, 'Cluster': Cluster}
