from flask import Blueprint, jsonify

bp = Blueprint('main', __name__)

@bp.route('/health')
def health():
    return jsonify({'status': 'ok', 'service': 'flask-api'}), 200

@bp.route('/info')
def info():
           return jsonify({
'service' : 'flask-api',
'env' : os.getenv('APP_ENV','development'),
'version' : '1.0.0',
}), 200
