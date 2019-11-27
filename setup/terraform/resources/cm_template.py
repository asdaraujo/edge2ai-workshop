'''
'''
import json
import logging
import os
import re
import yaml
from optparse import OptionParser, OptionGroup
from string import Template

# Represent None as empty instead of "null"
def represent_none(self, _):
    return self.represent_scalar('tag:yaml.org,2002:null', '')
yaml.add_representer(type(None), represent_none)

logging.basicConfig(level=logging.DEBUG)
LOG = logging.getLogger(__name__)

IDEMPOTENT_IDS = ['refName', 'name', 'clusterName', 'hostName', 'product']
TEMPLATES = {}

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
    template = Template(open(json_file).read())
    json_content = template.substitute(**configs)
    try:
        return json.loads(json_content)
    except:
        LOG.error('Failed to load file {}'.format(json_file))
        raise

def gen_var_template(template_names, templates, yaml_template):
    vars = {}
    for json_file in [templates[name] for name in template_names]:
        template = open(json_file).read()
        for var in re.findall(r'\${?([A-Za-z0-9_]*)}?', template):
            vars[var] = None

    if os.path.exists(yaml_template):
        vars.update(yaml.load(open(yaml_template)))

    output = open(yaml_template, 'w')
    output.write(yaml.dump(vars, default_flow_style=False))
    output.close()

def load_templates(template_dir):
    files = os.listdir(template_dir)
    json_paths = [os.path.join(template_dir, f) for f in files]
    common_templates = {}
    for template in json_paths:
        if re.match(r'.*\.[67]\.json$', template):
            template_name, cdh_version = re.match(r'.*?([^/.]*)\.([67])\.json$', template).groups()
            if cdh_version not in TEMPLATES:
                TEMPLATES[cdh_version] = {}
            TEMPLATES[cdh_version][template_name.upper()] = template
        else:
            template_name, = re.match(r'.*?([^/.]*)\.json$', template).groups()
            common_templates[template_name.upper()] = template
    for cdh_version in TEMPLATES:
        temp = common_templates.copy()
        temp.update(TEMPLATES[cdh_version])
        TEMPLATES[cdh_version] = temp

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
    for version in sorted(TEMPLATES):
        print('  CDH v{}:'.format(version))
        for template in sorted(TEMPLATES[version]):
            print('    - {}'.format(template))

def get_template(template_names, templates, config_file):
    # Get properties from environment variables and configuration file, if specified
    configs = {}
    configs.update(os.environ)
    if config_file:
        configs.update(yaml.load(open(config_file)))

    chosen_templates = []
    for template_name in template_names:
        chosen_templates.append(load_template(templates[template_name], configs))
    merged = merge_templates(chosen_templates)
    return json.dumps(merged, indent=2)

def main():
    (options, args) = parse_args()

    if options.template_dir is None:
        options.template_dir = os.path.join(os.path.dirname(__file__), 'templates')
    load_templates(options.template_dir)

    if options.cdh_major_version is None:
        LOG.error('The --cdh-major-version must be specified. Valid values are: 6 and 7')
        exit(1)
    elif options.cdh_major_version not in ['6', '7']:
        LOG.error('The only valid values for --cdh-major-version are 6 and 7')
        exit(1)

    templates = TEMPLATES[options.cdh_major_version]

    choices = set([t.upper() for a in args for t in a.split(',')])
    invalid_options = []
    for choice in choices:
        if choice not in templates:
            invalid_options.append(choice)
    if invalid_options:
        LOG.error('The following are not valid templates: {}'.format(', '.join(invalid_options)))
        print_valid_templates()
        exit(1)

    if options.validate_only:
        exit(0)

    if options.gen_var_template:
        gen_var_template(choices, templates, options.gen_var_template)
        exit(0)

    print(get_template(choices, templates, options.config_file))

if __name__ == '__main__':
    main()
