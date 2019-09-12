"""
Form definitions
"""

from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, SubmitField, HiddenField
from wtforms.validators import ValidationError, DataRequired, Email

class LoginForm(FlaskForm):
    """Login form
    """
    email = StringField('Email', validators=[DataRequired(), Email()])
    login_submit = SubmitField('Sign In')

class RegistrationForm(FlaskForm):
    """Registration form for new users
    """
    email = HiddenField('Email')
    email_confirmation = StringField('Confirm email', validators=[])
    full_name = StringField('Full name')
    company = StringField('Company')
    register_submit = SubmitField('Register')
    cancel = SubmitField('Cancel')

    def __init__(self, original_email, *args, **kwargs):
        super(RegistrationForm, self).__init__(*args, **kwargs)
        self.original_email = original_email

    def validate_email_confirmation(self, email_confirmation):
        """Check if password was confirmed successfully
        """
        if email_confirmation.data != self.original_email:
            raise ValidationError('Your email confirmation does not match the original one')

class PasswordForm(FlaskForm):
    """Password form for admins
    """
    email = HiddenField('Email')
    password = PasswordField('Password', validators=[DataRequired()])
    password_submit = SubmitField('Sign In')
