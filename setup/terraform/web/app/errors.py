"""
Default error handlers
"""
from flask import render_template, make_response, jsonify, request
from app import app, db

@app.errorhandler(500)
def internal_error(error):
    """Renders default Internal Error page
    """
    db.session.rollback()
    return render_template('500.html'), 500

@app.errorhandler(404)
def not_found(error):
    """Renders default 404 page
    """
    if request.path == '/api' or request.path.startswith('/api/'):
        return make_response(jsonify({'error': 'Not found'}), 404)
    else:
        return render_template('404.html'), 404

@app.errorhandler(400)
def error_400(error):
    """Renders default Processing Error page
    """
    return make_response(jsonify({'error': '400: %s' % (error,)}), 400)