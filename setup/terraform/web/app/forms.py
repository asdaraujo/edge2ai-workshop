"""
Form definitions
"""

from flask_wtf import FlaskForm
from wtforms import StringField, PasswordField, SubmitField, HiddenField
from wtforms.validators import ValidationError, DataRequired, Email, EqualTo

class LoginForm(FlaskForm):
    """Login form
    """
    email = StringField('Email', validators=[DataRequired(), Email()])
    password = PasswordField('Password', validators=[DataRequired()])
    login_submit = SubmitField('Sign In')

class RegistrationForm(FlaskForm):
    """Registration form for new users
    """
    email = HiddenField('Email')
    email_confirmation = StringField('Confirm email', validators=[])
    full_name = StringField('Full name')
    company = StringField('Company')
    new_password = PasswordField('New Password', validators=[DataRequired()])
    confirm_password = PasswordField('Confirm Password', validators=[DataRequired(), EqualTo('new_password', message='Passwords must match')])
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

class PasswordResetForm(FlaskForm):
    """Password reset form
    """
    email = HiddenField('Email')
    password = PasswordField('New Password', validators=[DataRequired()])
    confirm_password = PasswordField('Confirm Password', validators=[DataRequired(), EqualTo('password', message='Passwords must match')])
    password_submit = SubmitField('Submit')
