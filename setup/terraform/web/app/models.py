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
    is_admin = db.Column(db.Boolean)
    cluster_id = db.Column(db.Integer, db.ForeignKey('cluster.id'))

    def __repr__(self):
        return '<User {}>'.format(self.email)

    def set_password(self, password):
        """Set the user's password hash
        """
        self.password_hash = generate_password_hash(password)

    def check_password(self, password):
        """Check a password against the existing hash
        """
        return check_password_hash(self.password_hash, password)

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
    hostname = db.Column(db.String(256))
    ssh_user = db.Column(db.String(32))
    ssh_password = db.Column(db.String(64))
    ssh_private_key = db.Column(db.String(4096))
    user = db.relationship('User', backref='cluster', lazy='dynamic')

    def __repr__(self):
        return '<Cluster {} - {}>'.format(self.id, self.ip_address)

@login.user_loader
def load_user(user_id):
    """Indicates to LoginManager how the current user should be loaded
    """
    return User.query.get(int(user_id))
