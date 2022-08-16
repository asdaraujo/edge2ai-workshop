"""
View/Route implementations
"""

from flask import flash, jsonify, redirect, render_template, request, Response, url_for
from flask_httpauth import HTTPBasicAuth
from flask_login import current_user, login_user, logout_user, login_required
from sqlalchemy.exc import IntegrityError
from psycopg2.errors import UniqueViolation
from werkzeug.urls import url_parse
from app import app, db
from app.forms import LoginForm, RegistrationForm, PasswordResetForm
from app.models import User, Cluster, Config

basic_auth = HTTPBasicAuth()


@basic_auth.verify_password
def verify_password(email, pwd):
    """Verify the admin password, given the admin email and a password candidate
    """
    user = User.query.filter_by(email=email).first()
    if user is not None and user.check_password(pwd):
        return user


@app.route('/')
@app.route('/index')
@login_required
def index_page():
    """Home page
    """
    urls = []
    if current_user.cluster:
        urls = service_urls(current_user.cluster.namespace)
    return render_template('index.html', title='Home', service_urls=urls, user=current_user)


@app.route('/login', methods=['GET', 'POST'])
def login_page():
    """Handle user logins
    """
    if current_user.is_authenticated:
        return redirect(url_for('index_page'))
    form = LoginForm()
    if form.validate_on_submit():
        user = User.query.filter_by(email=form.email.data).first()
        next_page = request.args.get('next')
        if user is None:
            reg_code = Config.query.get(Config.REGISTRATION_CODE)
            if reg_code is None or not reg_code.check_hash(form.password.data):
                flash('Invalid username or password.')
                app.logger.warn(
                    "Invalid registration for user {} from IP {}".format(form.email.data, get_real_ip(request)))
                return redirect(url_for('login_page'))
            return redirect(url_for('register_and_login_page', next=next_page), code=307)
        else:
            if not user.check_password(form.password.data):
                flash('Invalid username or password.')
                app.logger.warn("Invalid login for user {} from IP {}".format(form.email.data, get_real_ip(request)))
                return redirect(url_for('login_page'))
            if user.force_password_reset:
                return redirect(url_for('password_reset_page', email=form.email.data), code=307)
        if not user.cluster:
            cluster_ids = [u.cluster_id for u in User.query.all() if u.cluster_id]
            user.cluster = Cluster.query.filter(~Cluster.id.in_(cluster_ids)).first()
        user.last_remote_ip = get_real_ip(request)
        db.session.commit()
        login_user(user)
        if not next_page or url_parse(next_page).netloc != '':
            next_page = url_for('index_page')
        return redirect(next_page)
    return render_template('login.html', title='Sign In', form=form)


@app.route('/passwordreset', methods=['POST'])
def password_reset_page():
    """Handle password reset
    """
    if not 'email' in request.form or not request.form['email']:
        return redirect(url_for('login_page'))
    form = PasswordResetForm()
    if 'password_submit' in request.form and form.validate_on_submit():
        next_page = request.args.get('next')
        user = User.query.filter_by(email=request.form['email']).first()
        if user is None:
            return redirect(url_for('login_page'))
        user.set_password(request.form['password'])
        user.force_password_reset = False
        db.session.commit()
        logout_user()
        flash('Password reset successfully.')
        if not next_page or url_parse(next_page).netloc != '':
            next_page = url_for('index_page')
        return redirect(next_page)
    return render_template('password.html', title='Reset Password', form=form)


@app.route('/register', methods=['POST'])
def register_and_login_page():
    """Handle user registration
    """
    if not 'email' in request.form:
        return redirect(url_for('login_page'))
    if current_user.is_authenticated or not 'email' in request.form:
        return redirect(url_for('index_page'))
    form = RegistrationForm(request.form['email'])
    next_page = request.args.get('next')
    if 'cancel' in request.form:
        return redirect(url_for('login_page', next=next_page))
    if 'register_submit' in request.form and form.validate_on_submit():
        user = User(email=form.email_confirmation.data, full_name=form.full_name.data,
                    company=form.company.data, is_admin=False, last_remote_ip=get_real_ip(request),
                    force_password_reset=False)
        user.set_password(form.new_password.data)
        db.session.add(user)
        if not user.cluster:
            cluster_ids = [u.cluster_id for u in User.query.all() if u.cluster_id]
            user.cluster = Cluster.query.filter(~Cluster.id.in_(cluster_ids)).first()
        db.session.commit()
        login_user(user)
        if not next_page or url_parse(next_page).netloc != '':
            next_page = url_for('index_page')
        return redirect(next_page)
    return render_template('register.html', title='Sign In', form=form)


@app.route('/logout')
@login_required
def logout_page():
    """Handle logout
    """
    logout_user()
    return redirect(url_for('login_page'))


@app.route('/download/<cluster_id>')
@login_required
def download_page(cluster_id):
    """Handle download of the SSH private key
    """
    cluster = Cluster.query.filter_by(id=cluster_id).first()
    if cluster and cluster.ssh_private_key:
        return Response(
            cluster.ssh_private_key,
            mimetype="text/json",
            headers={"Content-disposition": "attachment; filename=workshop.pem"})
    return None


@app.route('/users', methods=['GET', 'POST'])
@login_required
def users_page():
    """Handle user list page
    """
    if not current_user.is_admin:
        return redirect(url_for('index_page'))
    if request.method == 'POST' and len(request.form) == 1:
        uid_str, action = list(request.form.items())[0]
        user_id = int(uid_str)
        user = User.query.filter_by(id=user_id).first()
        if action == 'Delete':
            db.session.delete(user)
            flash('User {} has been deleted.'.format(user.email))
        elif action == 'Reset Pwd':
            reg_code = Config.query.get(Config.REGISTRATION_CODE)
            if reg_code is not None:
                user.password_hash = reg_code.value
                user.force_password_reset = True
                flash('User password was reset to the registration code.')
        db.session.commit()
        return redirect(url_for('users_page'), code=303)
    users = User.query.all()
    return render_template('users.html', users=users)


@app.route('/clusters', methods=['GET', 'POST'])
@login_required
def clusters_page():
    """Handle cluster list page
    """
    if not current_user.is_admin:
        return redirect(url_for('index_page'))
    if request.method == 'POST' and len(request.form) == 1:
        cluster_id = int([f for f in request.form][0])
        cluster = Cluster.query.filter_by(id=cluster_id).first()
        db.session.delete(cluster)
        db.session.commit()
        return redirect(url_for('clusters_page'), code=303)
    clusters = Cluster.query.all()
    return render_template('clusters.html', clusters=clusters, code=303)


# REST

@app.route('/api/admins', methods=['POST'])
def create_admin():
    """Create the admin user
    """
    has_email = 'email' in request.json and isinstance(request.json['email'], str)
    has_full_name = 'full_name' in request.json and isinstance(request.json['full_name'], str)
    has_company = 'company' in request.json and isinstance(request.json['company'], str)
    has_password = 'password' in request.json and isinstance(request.json['password'], str)
    if not request.json or not has_email or not has_full_name or \
            not has_company or not has_password:
        return jsonify({'reason': 'No JSON payload or payload is invalid.'}), 400
    admin = User.query.filter_by(is_admin=True).first()
    if admin:
        return jsonify({'reason': 'An admin account already exists.'}), 400
    user = User.query.filter_by(email=request.json['email']).first()
    if user:
        user.is_admin = True
    else:
        user = User(email=request.json['email'], full_name=request.json['full_name'],
                    company=request.json['company'], is_admin=True,
                    force_password_reset=False)
    user.set_password(request.json['password'])
    db.session.add(user)
    db.session.commit()
    return jsonify({'success': True, 'message': 'Admin user created successfully.'})


@app.route('/api/clusters', methods=['POST'])
@basic_auth.login_required
def add_cluster():
    """Add a cluster
    """
    if not basic_auth.current_user().is_admin:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 403

    has_ip_address = 'ip_address' in request.json and isinstance(request.json['ip_address'], str)
    has_namespace = 'namespace' in request.json and isinstance(request.json['namespace'], str)
    has_instance_id = 'instance_id' in request.json and isinstance(request.json['instance_id'], str)
    has_hostname = 'hostname' in request.json and isinstance(request.json['hostname'], str)
    has_ssh_user = 'ssh_user' in request.json and isinstance(request.json['ssh_user'], str)
    has_ssh_pwd = 'ssh_password' in request.json and isinstance(request.json['ssh_password'], str)
    has_ssh_pk = 'ssh_private_key' in request.json and \
                 isinstance(request.json['ssh_private_key'], str)
    if not request.json or not has_ip_address or not has_namespace or not has_instance_id or \
            not has_hostname or not has_ssh_user or not has_ssh_pwd or not has_ssh_pk:
        return jsonify({'success': False, 'message': 'No JSON payload or payload is invalid'}), 400
    try:
        cluster = Cluster(ip_address=request.json['ip_address'],
                          namespace=request.json['namespace'],
                          instance_id=request.json['instance_id'],
                          hostname=request.json['hostname'],
                          ssh_user=request.json['ssh_user'],
                          ssh_password=request.json['ssh_password'],
                          ssh_private_key=request.json['ssh_private_key'])
        db.session.add(cluster)
        db.session.commit()
        return jsonify({'success': True, 'message': 'Cluster created successfully.'})
    except IntegrityError as exc:
        if isinstance(exc.orig, UniqueViolation) and isinstance(exc.orig.args, tuple) and len(exc.orig.args) == 1:
            msg = exc.orig.args
            return jsonify({'success': False, 'message': msg}), 400
        raise exc


@app.route('/api/config', methods=['POST', 'DELETE'])
@basic_auth.login_required
def config():
    """Add a cluster
    """
    if not basic_auth.current_user().is_admin:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 403

    has_attr = 'attr' in request.json and isinstance(request.json['attr'], str)
    attr = request.json['attr'] if has_attr else None
    has_value = 'value' in request.json and isinstance(request.json['value'], str)
    value = request.json['value'] if has_value else None
    is_sensitive = 'sensitive' in request.json and bool(request.json['sensitive'])
    if request.method == 'POST':
        if not request.json or not has_attr or not has_value:
            return jsonify({'success': False, 'message': 'No JSON payload or payload is invalid'}), 400
        try:
            config = Config.query.get(attr)
            if not config:
                config = Config(attr=attr, value='')
                db.session.add(config)
            if is_sensitive:
                config.set_hash(value)
            else:
                config.value = value
            db.session.commit()
            return jsonify({'success': True, 'message': 'Configuration created successfully.'})
        except IntegrityError as exc:
            raise exc
    elif request.method == 'DELETE':
        if not request.json or not has_attr:
            return jsonify({'success': False, 'message': 'No JSON payload or payload is invalid.'}), 400
        try:
            config = Config.query.get(attr)
            if config is None:
                return jsonify({'success': False, 'message': 'Configuration does not exist.'}), 400
            db.session.delete(config)
            db.session.commit()
            return jsonify({'success': True, 'message': 'Configuration deleted successfully.'})
        except IntegrityError as exc:
            raise exc


@app.route('/api/ips', methods=['GET'])
@basic_auth.login_required
def ips():
    """Add a cluster
    """
    if not basic_auth.current_user().is_admin:
        return jsonify({'success': False, 'message': 'Unauthorized'}), 403

    all_ips = set([u.last_remote_ip for u in User.query.all() if u.last_remote_ip])
    return jsonify({'success': True, 'ips': list(all_ips)})


@app.route('/api/ping', methods=['GET'])
def ping():
    """Respond to a ping
    """
    return jsonify({'success': True, 'message': 'Pong!'})


def get_real_ip(request):
    """Get client IP
    """
    if 'X-Real-Ip' in request.headers:
        return request.headers['X-Real-Ip']
    return request.remote_addr


def service_urls(namespace):
    """Return the service URLs
    """
    urls = Config.query.get(Config.NAMESPACE_URLS_PREFIX + namespace)
    if urls:
        return [s.split('=')[1:] for s in urls.value.split(',')]
    return []
