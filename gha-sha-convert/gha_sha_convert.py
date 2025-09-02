#!/usr/bin/env python3
"""GitHub Actions SHA Converter

A pre-commit hook to convert GitHub Actions references to use SHA hashes
for supply chain security while preserving semantic version comments.
"""

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


class GitHubActionsConverter:
    """Converts GitHub Actions references to SHA-pinned versions."""

    def __init__(self, token: Optional[str] = None, force: bool = False):
        """Initialize the converter.

        Args:
            token: GitHub token for API access
            force: Force conversion even if already using SHA
        """
        self.token = token or os.environ.get('GITHUB_TOKEN')
        self.force = force
        self.session = self._create_session()
        self.cache: Dict[str, str] = {}

    def _create_session(self) -> requests.Session:
        """Create a requests session with retry strategy."""
        session = requests.Session()
        retry_strategy = Retry(
            total=3,
            status_forcelist=[429, 500, 502, 503, 504],
            backoff_factor=1
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        session.mount("http://", adapter)
        session.mount("https://", adapter)

        if self.token:
            session.headers.update({'Authorization': f'token {self.token}'})

        return session

    def find_yaml_files(self, base_path: Path) -> List[Path]:
        """Find all YAML workflow and action files."""
        patterns = [
            '.github/workflows/*.yml',
            '.github/workflows/*.yaml',
            '.github/actions/*.yml',
            '.github/actions/*.yaml'
        ]

        files = []
        for pattern in patterns:
            files.extend(base_path.glob(pattern))
        return files

    def extract_owner_repo(self, action_ref: str) -> str:
        """Extract owner/repo from action reference.

        Args:
            action_ref: Action reference like 'owner/repo/subpath'

        Returns:
            Owner/repo portion
        """
        parts = action_ref.split('/')
        if len(parts) >= 2:
            return f"{parts[0]}/{parts[1]}"
        return action_ref

    def is_semver(self, version: str) -> bool:
        """Check if version string is semantic version."""
        return len(version.split('.')) >= 3

    def is_sha(self, version: str) -> bool:
        """Check if version string is a SHA hash."""
        if len(version) != 40:
            return False
        return bool(re.match(r'^[a-f0-9]+$', version))

    def get_sha_for_tag(self, owner_repo: str, tag: str) -> Optional[str]:
        """Get SHA hash for a given tag.

        Args:
            owner_repo: Repository in format 'owner/repo'
            tag: Git tag name

        Returns:
            SHA hash or None if not found
        """
        cache_key = f"{owner_repo}@{tag}"
        if cache_key in self.cache:
            return self.cache[cache_key]

        try:
            # First try getting the tag reference
            url = f"https://api.github.com/repos/{owner_repo}/git/refs/tags/{tag}"
            response = self.session.get(url)

            if response.status_code == 404:
                print(f"Warning: Tag {tag} not found for {owner_repo}")
                return None
            elif response.status_code == 429:
                print("Error: Rate limit exceeded")
                sys.exit(1)
            elif response.status_code >= 400:
                print(f"Error: API request failed with status {response.status_code}")
                return None

            data = response.json()

            # Handle both single tag and array responses
            if isinstance(data, list):
                data = data[0]

            obj_type = data.get('object', {}).get('type')

            if obj_type == 'tag':
                # Annotated tag - need to get the commit it points to
                tag_url = data['object']['url']
                tag_response = self.session.get(tag_url)
                if tag_response.status_code == 200:
                    tag_data = tag_response.json()
                    sha = tag_data.get('object', {}).get('sha')
                else:
                    return None
            else:
                # Direct commit reference
                sha = data.get('object', {}).get('sha')

            if sha and len(sha) == 40:
                self.cache[cache_key] = sha
                return sha

        except Exception as e:
            print(f"Error getting SHA for {owner_repo}@{tag}: {e}")

        return None

    def find_best_version_for_sha(self, owner_repo: str, sha: str,
                                 current_ref: str) -> str:
        """Find the best semantic version for a SHA.

        Args:
            owner_repo: Repository in format 'owner/repo'
            sha: SHA hash to find version for
            current_ref: Current reference being used

        Returns:
            Best version string for comments
        """
        try:
            url = f"https://api.github.com/repos/{owner_repo}/tags"
            response = self.session.get(url)

            if response.status_code != 200:
                return current_ref

            tags = response.json()
            matching_tags = [
                tag['name'] for tag in tags
                if tag.get('commit', {}).get('sha') == sha
            ]

            if not matching_tags:
                return current_ref

            # Try to find a semantic version that matches the pattern
            if current_ref and not self.is_semver(current_ref):
                dots = current_ref.count('.')
                if dots == 0:
                    pattern = re.compile(rf"{re.escape(current_ref)}\.\d+\.\d+")
                elif dots == 1:
                    pattern = re.compile(rf"{re.escape(current_ref)}\.\d+")
                else:
                    pattern = None

                if pattern:
                    pattern_matches = [tag for tag in matching_tags if pattern.match(tag)]
                    if pattern_matches:
                        return sorted(pattern_matches, reverse=True)[0]

            # Sort tags and return the first (most recent) semantic version
            semver_tags = [tag for tag in matching_tags if self.is_semver(tag)]
            if semver_tags:
                # Sort by semantic version properly - higher versions first
                def version_key(v):
                    # Remove 'v' prefix if present and split into parts
                    clean_v = v.lstrip('v')
                    try:
                        # Only take the main version parts (ignore pre-release suffixes)
                        main_version = clean_v.split('-')[0]
                        parts = [int(x) for x in main_version.split('.')]
                        # Pad to 3 parts if needed
                        while len(parts) < 3:
                            parts.append(0)
                        return tuple(parts)
                    except:
                        return (0, 0, 0)

                return sorted(semver_tags, key=version_key, reverse=True)[0]

            # Fall back to any version
            return sorted(matching_tags, reverse=True)[0]

        except Exception as e:
            print(f"Error finding version for {owner_repo}@{sha}: {e}")
            return current_ref

    def process_file(self, file_path: Path) -> int:
        """Process a single YAML file.

        Args:
            file_path: Path to the YAML file

        Returns:
            Number of changes made
        """
        print(f"\nProcessing file: {file_path}")

        try:
            content = file_path.read_text()
        except Exception as e:
            print(f"Error reading {file_path}: {e}")
            return 0

        # Find all action references
        pattern = r'uses: ([^@\s]+)@([^\s#]+)(?:\s*#\s*([^\s]+))?'
        matches = re.findall(pattern, content)

        if not matches:
            return 0

        covered: Set[str] = set()
        changes = 0

        for action_ref, version, comment_version in matches:
            original_line = f"uses: {action_ref}@{version}"
            if comment_version:
                original_line += f" # {comment_version}"

            if original_line in covered:
                print(f"Skipping {original_line}, already processed")
                continue

            covered.add(original_line)

            owner_repo = self.extract_owner_repo(action_ref)

            # Determine the reference to use for SHA lookup
            ref = comment_version if comment_version else version

            # Skip if already using SHA and has semantic version comment
            if (self.is_sha(version) and not self.force and
                comment_version and self.is_semver(comment_version)):
                print(f"{owner_repo}@{version} # {comment_version} "
                      "already using SHA with semver, skipping")
                continue

            # Get SHA for the reference
            if self.is_sha(version) and not self.force:
                sha = version
            else:
                if not self.token:
                    print("Warning: No GitHub token provided, skipping API calls")
                    continue

                sha = self.get_sha_for_tag(owner_repo, ref)
                if not sha:
                    continue

            # Find best version for comment
            final_version = self.find_best_version_for_sha(
                owner_repo, sha, ref
            )

            # Create the replacement
            new_line = f"uses: {action_ref}@{sha} # {final_version}"

            if original_line != new_line:
                print(f"Updating '{original_line}' -> '{new_line}'")
                content = content.replace(original_line, new_line)
                changes += 1

        if changes > 0:
            try:
                file_path.write_text(content)
                print(f"Updated {file_path} with {changes} changes")
            except Exception as e:
                print(f"Error writing {file_path}: {e}")
                return 0

        return changes

    def process_directory(self, base_path: Path) -> int:
        """Process all YAML files in a directory.

        Args:
            base_path: Base directory to search

        Returns:
            Total number of changes made
        """
        yaml_files = self.find_yaml_files(base_path)

        if not yaml_files:
            print("No YAML workflow or action files found")
            return 0

        total_changes = 0
        for file_path in yaml_files:
            total_changes += self.process_file(file_path)

        return total_changes


def main():
    """Main entry point for the pre-commit hook."""
    parser = argparse.ArgumentParser(
        description="Convert GitHub Actions to use SHA-pinned versions"
    )
    parser.add_argument(
        '--force',
        action='store_true',
        help="Force conversion even if already using SHA"
    )
    parser.add_argument(
        'files',
        nargs='*',
        help="Specific files to process (default: all workflow files)"
    )

    args = parser.parse_args()

    # Check for GitHub token
    token = os.environ.get('GITHUB_TOKEN')
    if not token:
        print("Warning: GITHUB_TOKEN not set. Some features may not work.")

    converter = GitHubActionsConverter(token=token, force=args.force)

    if args.files:
        # Process specific files
        total_changes = 0
        for file_path in args.files:
            path = Path(file_path)
            if path.exists() and path.suffix in ['.yml', '.yaml']:
                total_changes += converter.process_file(path)
    else:
        # Process all workflow files in current directory
        total_changes = converter.process_directory(Path('.'))

    if total_changes > 0:
        print(f"\nTotal changes made: {total_changes}")
        sys.exit(1)  # Exit with error to fail pre-commit if changes were made
    else:
        print("\nNo changes needed")
        sys.exit(0)


if __name__ == '__main__':
    main()
