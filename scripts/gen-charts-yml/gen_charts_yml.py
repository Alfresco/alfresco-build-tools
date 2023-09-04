import os
import argparse
import yaml

DEFAULT_SRC_PATH = 'charts'
DEFAULT_YAML_PATH = 'charts.yaml'
DEFAULT_ROOT_KEY = 'charts'

def list_subfolders(folder_path):
    """
    List subfolders and return a dict, each key is a folder name
    """
    return {f.name for f in os.scandir(folder_path) if f.is_dir()}


def load_existing_yaml(file_path):
    """
    Load an existing charts yml or return an empty one
    """
    default_charts = {'charts': {}}
    try:
        with open(file_path, 'r', encoding="utf-8") as yaml_file:
            existing_file_data = yaml.safe_load(yaml_file)
            return existing_file_data if existing_file_data else default_charts
    except FileNotFoundError:
        return default_charts


def write_yaml_file(data, file_path):
    """
    Dump yaml to disk
    """
    with open(file_path, 'w', encoding="utf-8") as yaml_file:
        yaml.dump(data, yaml_file, default_flow_style=False)


def main():
    """
    Enumerate subfolders in a given folder, update a dictionary where each key
    is the name of a subfolder in a given yaml file
    """
    parser = argparse.ArgumentParser(
        description='Create or update a YAML file with subfolder names.')

    parser.add_argument('--src', default=DEFAULT_SRC_PATH,
                        help='Path to the folder containing subfolders.')
    parser.add_argument('--yaml', default=DEFAULT_YAML_PATH,
                        help='Path to the YAML file to write.')
    parser.add_argument('--root-name', default=DEFAULT_ROOT_KEY,
                        help='The root key inside the YAML file')

    args = parser.parse_args()

    subfolders = list_subfolders(args.src)
    data = {args.root_name: subfolders}

    existing_data = load_existing_yaml(args.yaml)
    for entry in data[args.root_name]:
        existing_data[args.root_name].setdefault(entry)

    write_yaml_file(existing_data, args.yaml)


if __name__ == "__main__":
    main()
