"""
Application module
"""

from logging import INFO, Formatter
from logging.handlers import SMTPHandler, RotatingFileHandler
import os
from flask import Flask
from flask_bootstrap import Bootstrap
from flask_login import LoginManager
from flask_migrate import Migrate
from flask_sqlalchemy import SQLAlchemy
from dotenv import load_dotenv, find_dotenv

load_dotenv(find_dotenv())
from config import Config

app = Flask(__name__)
app.config.from_object(Config)
db = SQLAlchemy(app)
migrate = Migrate(app, db)
login = LoginManager(app)
login.login_view = 'login_page'
bootstrap = Bootstrap(app)

from app import routes, models, errors # pylint: disable=wrong-import-position

if not app.debug:
    if not os.path.exists('logs'):
        os.mkdir('logs')
    file_handler = RotatingFileHandler('logs/workshop.log', maxBytes=10000000, backupCount=10)
    file_handler.setFormatter(Formatter(
        '%(asctime)s %(levelname)s: %(message)s [in %(pathname)s:%(lineno)d]'))
    file_handler.setLevel(INFO)
    app.logger.addHandler(file_handler)

    app.logger.setLevel(INFO)
    app.logger.info('Workshop server startup')
