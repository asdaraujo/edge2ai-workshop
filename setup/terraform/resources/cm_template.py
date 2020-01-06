'''
'''
import json
import logging
import os
import re
import yaml
from optparse import OptionParser, OptionGroup
from jinja2 import Environment, FileSystemLoader, StrictUndefined
from jinja2.exceptions import UndefinedError

# Represent None as empty instead of "null"
def represent_none(self, _):
    return self.represent_scalar('tag:yaml.org,2002:null', '')
yaml.add_representer(type(None), represent_none)

logging.basicConfig(level=logging.DEBUG)
LOG = logging.getLogger(__name__)

IDEMPOTENT_IDS = ['refName', 'name', 'clusterName', 'hostName', 'product']
REQUIRES_PREFIX = 'REQUIRES_CDH_MAJOR_VERSION_'
TEMPLATES = {}
TEMPLATE_DIR = './templates'

JINJA2_ENV = None

def jinja2_env():
    global JINJA2_ENV
    if not JINJA2_ENV:
        raise RuntimeError('Jinja2 environment has not been initialized yet.')
    return JINJA2_ENV

def init_jinja2_env(template_dir):
    global JINJA2_ENV
    JINJA2_ENV = Environment(loader=FileSystemLoader(template_dir), undefined=StrictUndefined)

def merge_templates(templates):
    merged = {}
    for template in templates:
        update_object(merged, template)
    return merged

def update_object(base, template, breadcrumbs=''):
    if isinstance(base, dict) and isinstance(template, dict):
        update_dict(base, template, breadcrumbs)
        return True
    elif isinstance(base, list) and isinstance(template, list):
        update_list(base, template, breadcrumbs)
        return True
    return False

def update_dict(base, template, breadcrumbs=''):
    for key, value in template.items():
        crumb = breadcrumbs + '/' + key
        if key in IDEMPOTENT_IDS:
            if base[key] != value:
                LOG.error('Objects with distinct IDs should not be merged: ' + crumb)
            continue
        if key not in base:
            base[key] = value
        elif not update_object(base[key], value, crumb) and base[key] != value:
            LOG.warn("Value being overwritten for key [%s], Old: [%s], New: [%s]", crumb, base[key], value)
            base[key] = value

def update_list(base, template, breadcrumbs=''):
    for item in template:
        if isinstance(item, dict):
            for attr in IDEMPOTENT_IDS:
                if attr in item:
                    idempotent_id = attr
                    break
            else:
                idempotent_id = None
            if idempotent_id:
                namesake = [i for i in base if i[idempotent_id] == item[idempotent_id]]
                if namesake:
                    #LOG.warn("List item being replaced, Old: [%s], New: [%s]", namesake[0], item)
                    update_dict(namesake[0], item, breadcrumbs + '/[' + idempotent_id + '=' + item[idempotent_id] + ']')
                    continue
        base.append(item)

def load_template(json_file, configs):
    template = jinja2_env().get_template(json_file)
    try:
        json_content = template.render(**configs)
        return json.loads(json_content)
    except UndefinedError as exc:
        m = re.match('.*' + REQUIRES_PREFIX + '([0-9]*).*is undefined', exc.message)
        if m:
            template = re.sub(r'\..*', '', json_file).upper()
            raise RuntimeError('Template {} is only valid for CDH version {}'.format(template, m.groups()[0]))
        raise
    except:
        LOG.error('Failed to load file {}'.format(json_file))
        raise

def gen_var_template(template_names, yaml_template):
    vars = {}
    for json_file in [TEMPLATES[name] for name in template_names]:
        template = open(os.path.join(TEMPLATE_DIR, json_file)).read()
        for var in re.findall(r'{{ *([A-Za-z0-9_]*) *}}', template):
            if not var.startswith(REQUIRES_PREFIX):
                vars[var] = None

    if os.path.exists(yaml_template):
        vars.update(yaml.load(open(yaml_template)))

    output = open(yaml_template, 'w')
    output.write(yaml.dump(vars, default_flow_style=False))
    output.close()

def load_templates(template_dir):
    global TEMPLATES, TEMPLATE_DIR
    TEMPLATE_DIR = template_dir
    files = os.listdir(template_dir)
    for template_file in files:
        if re.match(r'.*\.json$', template_file):
            template_name, = re.match(r'.*?([^/.]*)\.json$', template_file).groups()
            TEMPLATES[template_name.upper()] = template_file
    for template in TEMPLATES:
        os.environ['HAS_' + template] = ''

def parse_args():
    parser = OptionParser(usage='%prog [options] <json_file> ...')

    parser.add_option('--config-file', action='store', type='string',
                      dest='config_file', default=None,
                      metavar='PATH',
                      help='Path of the YAML configuration file. '
                           'Default: defaults.yaml')
    parser.add_option('--template-dir', action='store', type='string',
                      dest='template_dir', default=None,
                      metavar='PATH',
                      help='Path of the directory where templates are stored. '
                           'Default: ./templates')
    parser.add_option('--cdh-major-version', action='store', type='string',
                      dest='cdh_major_version',
                      metavar='VERSION',
                      help='Major version of the CDH cluster for which the template will be generated. '
                           'Valid values: 6 and 7')
    parser.add_option('--validate-only', action='store_true',
                      dest='validate_only',
                      help='Only validate if the specified services are valid.')
    parser.add_option('--gen-var-template', action='store', type='string',
                      dest='gen_var_template', default=None,
                      metavar='FILE',
                      help='Generates a YAML file with the required variables for the given templates.')
    return parser.parse_args()

def print_valid_templates():
    print('Valid template names are:')
    for template in sorted(TEMPLATES):
        requires = re.findall(REQUIRES_PREFIX + '.', open(os.path.join(TEMPLATE_DIR, TEMPLATES[template])).read())
        print('    - {} {}'.format(template, '({})'.format(', '.join(requires)) if requires else ''))

def fix_dependencies(template_dir, selected_services):
    # Load dependencies file
    dep_file = os.path.join(template_dir, 'dependencies')
    dependencies = {}
    with open(dep_file) as deps:
        for line in deps:
            line = line.rstrip()
            m = re.match(r'^ *([^ ]*)  *requires  *([^ ]*) *$', line)
            if m:
                svc, deps = m.groups()
                dependencies[svc] = deps.split(',')
            else:
                LOG.error('Invalid line in dependencies file: %s', line)

    svc_set = set(selected_services)
    while True:
        base_set = svc_set.copy()
        for svc in base_set.union(['all']):
            for dep in dependencies.get(svc, []):
                if dep not in svc_set:
                    svc_set.add(dep)
                    LOG.info("Adding service %s since it is required by %s", dep, svc)
        if svc_set == base_set:
            break

    return list(svc_set)

def get_template(template_names, config_file):
    # Get properties from environment variables and configuration file, if specified
    configs = {}
    configs.update(os.environ)
    if config_file:
        configs.update(yaml.load(open(config_file)))

    chosen_templates = []
    for template_name in template_names:
        chosen_templates.append(load_template(TEMPLATES[template_name], configs))
    merged = merge_templates(chosen_templates)
    return json.dumps(merged, indent=2)

def main():
    (options, args) = parse_args()

    if options.template_dir is None:
        options.template_dir = os.path.join(os.path.dirname(__file__), 'templates')
    init_jinja2_env(options.template_dir)
    load_templates(options.template_dir)

    if options.cdh_major_version is None:
        LOG.error('The --cdh-major-version must be specified. Valid values are: 6 and 7')
        exit(1)
    elif options.cdh_major_version not in ['6', '7']:
        LOG.error('The only valid values for --cdh-major-version are 6 and 7')
        exit(1)
    os.environ['CDH_MAJOR_VERSION'] = options.cdh_major_version
    os.environ[REQUIRES_PREFIX + options.cdh_major_version] = ''

    choices = set([t.upper() for a in args for t in a.split(',')])
    for choice in choices:
        os.environ['HAS_' + choice] = '1'
    invalid_options = []
    for choice in choices:
        if choice not in TEMPLATES:
            invalid_options.append(choice)
    if invalid_options:
        LOG.error('The following are not valid templates: {}'.format(', '.join(invalid_options)))
        print_valid_templates()
        exit(1)

    if options.gen_var_template:
        gen_var_template(choices, options.gen_var_template)
        exit(0)

    choices = fix_dependencies(options.template_dir, choices)

    output = get_template(choices, options.config_file)
    if options.validate_only:
        exit(0)
    print(output)

if __name__ == '__main__':
    main()
