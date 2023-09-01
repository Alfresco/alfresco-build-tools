import os
import argparse
import yaml

DEFAULT_SRC_PATH = 'charts'
DEFAULT_YAML_PATH = 'charts.yaml'

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
    # Create argument parser
    parser = argparse.ArgumentParser(
        description='Create or update a YAML file with subfolder names.')

    # Add command-line arguments for folder path and YAML file path
    parser.add_argument('--src', default=DEFAULT_SRC_PATH,
                        help='Path to the folder containing subfolders.')
    parser.add_argument('--yaml', default=DEFAULT_YAML_PATH,
                        help='Path to the YAML file to write.')

    # Parse the command-line arguments
    args = parser.parse_args()

    subfolders = list_subfolders(args.src)
    data = {"charts": subfolders}

    existing_data = load_existing_yaml(args.yaml)
    for entry in data['charts']:
        existing_data['charts'].setdefault(entry)

    write_yaml_file(existing_data, args.yaml)


if __name__ == "__main__":
    main()
