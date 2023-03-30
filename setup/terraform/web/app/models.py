"""
Object models
"""
from hashlib import md5
from flask_login import UserMixin
from werkzeug.security import generate_password_hash, check_password_hash
from app import db, login

class User(UserMixin, db.Model):
    """User model
    """
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(120), index=True, unique=True)
    full_name = db.Column(db.String(120))
    company = db.Column(db.String(120))
    password_hash = db.Column(db.String(128))
    force_password_reset = db.Column(db.Boolean)
    is_admin = db.Column(db.Boolean)
    cluster_id = db.Column(db.Integer, db.ForeignKey('cluster.id'))
    last_remote_ip = db.Column(db.String(15))

    def __repr__(self):
        return '<User {}>'.format(self.email)

    def set_password(self, password):
        """Set the user's password hash
        """
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        """Check a password against the existing hash
        """
        try:
            return check_password_hash(self.password_hash, password)
        except:
            return False

    def avatar(self, size):
        """Return the avatar URL
        """
        digest = md5(self.email.lower().encode('utf-8')).hexdigest()
        return 'https://www.gravatar.com/avatar/{}?d=identicon&s={}'.format(
            digest, size)

class Cluster(db.Model):
    """Cluster model
    """
    id = db.Column(db.Integer, primary_key=True)
    ip_address = db.Column(db.String(15), unique=True)
    ecs_ip_address = db.Column(db.String(15))
    namespace = db.Column(db.String(128))
    instance_id = db.Column(db.Integer) # cluster ID within the namespace
    hostname = db.Column(db.String(256))
    ssh_user = db.Column(db.String(32))
    ssh_password = db.Column(db.String(64))
    ssh_private_key = db.Column(db.String(4096))
    user = db.relationship('User', backref='cluster', lazy='dynamic')
    __table_args__ = (
        db.UniqueConstraint('namespace', 'instance_id', name='uq_namespace_instance'),
    )

    def __repr__(self):
        return '<Cluster {} - {}:{} - {}>'.format(self.id, self.namespace, self.instance_id, self.ip_address)

class Config(db.Model):
    """Config model
    """
    attr = db.Column(db.String(128), primary_key=True)
    value = db.Column(db.String(4096))

    # Attributes list
    REGISTRATION_CODE = 'registration.code'
    NAMESPACE_URLS_PREFIX = 'namespace.service.urls.'

    def set_hash(self, value):
        """Stores the hash of a value
        """
        self.value = generate_password_hash(value)

    def check_hash(self, value):
        """Check value against the existing hash
        """
        try:
            return check_password_hash(self.value, value)
        except:
            return False

    def __repr__(self):
        return '<Config: {}={}>'.format(self.attr, self.value)

@login.user_loader
def load_user(user_id):
    """Indicates to LoginManager how the current user should be loaded
    """
    return User.query.get(int(user_id))
