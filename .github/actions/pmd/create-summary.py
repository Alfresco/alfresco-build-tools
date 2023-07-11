#!/usr/bin/env python

import argparse
from collections import Counter, defaultdict
import os
import re
import tempfile

parser = argparse.ArgumentParser(description='Create a summary of differences between two PMD output files.')
parser.add_argument('-o', '--old', help='The location of the old PMD report')
parser.add_argument('-n', '--new', help='The location of the new PMD report')
parser.add_argument('-d', '--diff', help='The location of the diff file')
parser.add_argument('-r', '--root', default='', help='The absolute path of the root of the modified repository')
parser.add_argument('-t', '--title', default='Summary of PMD differences', help='A title for the report')
args = parser.parse_args()

def next_line(lines, line_number):
    """Get the next line from a list of lines and return an incremented line number."""
    if line_number >= len(lines):
        return '', len(lines)
    return lines[line_number][:-1], line_number + 1

def path_from_line(line):
    """Handle paths starting with a/ or b/ as well as /dev/null."""
    return None if line == '/dev/null' else line[2:]

def extract_block_details(line):
    """Extract the start and length of the diff block from the header line."""
    detail_section = line.split('@@')[1].strip().strip('-')
    old_details, new_details = detail_section.split(' +')
    old_start, old_length = old_details.split(',')
    new_start, new_length = new_details.split(',')
    return int(old_start), int(old_length), int(new_start), int(new_length)

# Create maps from the file path to the list of line numbers that have been changed.
old_line_numbers = defaultdict(list)
new_line_numbers = defaultdict(list)
with open(args.diff) as diff_file:
    line_number = 0
    all_diff_lines = diff_file.readlines()
    while line_number < len(all_diff_lines):
        line, line_number = next_line(all_diff_lines, line_number)
        if line.startswith('--- '):
            old_path = path_from_line(line[4:])
            line, line_number = next_line(all_diff_lines, line_number)
            new_path = path_from_line(line[4:])
            line, line_number = next_line(all_diff_lines, line_number)
            while re.match(r'^@@ -[0-9]*,[0-9]* \+[0-9]*,[0-9]* @@.*', line):
                old_start, old_length, new_start, new_length = extract_block_details(line)
                # Track the position of each line on both sides of the diff.
                old_position, new_position = old_start, new_start
                while old_position < old_start + old_length or new_position < new_start + new_length:
                    line, line_number = next_line(all_diff_lines, line_number)
                    # Within a diff block then lines starting with space are unchanged. Those with + or - are only on one side of the diff.
                    if line.startswith(' '):
                        old_position += 1
                        new_position += 1
                    elif line.startswith('-'):
                        old_line_numbers[old_path].append(old_position)
                        old_position += 1
                    elif line.startswith('+'):
                        new_line_numbers[new_path].append(new_position)
                        new_position += 1
                line, line_number = next_line(all_diff_lines, line_number)

def summarise_report(filename):
    """Create a count of the violation types and a map from the type to the details of all violations."""
    violation_count = Counter()
    details = defaultdict(list)
    with open(filename) as report:
        for line in report.readlines():
            columns = line.strip().split(':\t')
            reference, rule, description = columns
            violation_count[rule] += 1
            details[rule].append((reference, description))
    return violation_count, details

old_violation_count, _ = summarise_report(args.old)
new_violation_count, new_details = summarise_report(args.new)

def log(line, pmd_summary_file):
    """Output the given summary line to stdout and the pmd_summary_file"""
    print(line)
    pmd_summary_file.write(line + '\n')

difference = new_violation_count - old_violation_count
temp_dir = tempfile.mkdtemp()
pmd_summary_path = f'{temp_dir}/pmd-summary.txt'
with open(pmd_summary_path, 'w') as pmd_summary_file:
    log(args.title, pmd_summary_file)
    for rule, delta in difference.most_common():
        if delta > 0:
            log(f'\n*** {delta} new {rule} violations ***\n', pmd_summary_file)
            violations_found = 0
            for reference, description in new_details[rule]:
                path, line_number = reference.replace(args.root, '').split(':')
                if path in new_line_numbers and int(line_number) in new_line_numbers[path]:
                    log(f'{reference} {description}', pmd_summary_file)
                    violations_found += 1
            if violations_found < delta:
                log('Specific line causing violation could not be found', pmd_summary_file)
        else:
            resolved_count = -delta
            log(f'\n*** {resolved_count} violations of {rule} have been resolved ***\n', pmd_summary_file)

    # Append full list of issues in the latest scan.
    pmd_summary_file.write('\n\n=== Full list of issues found in the latest code (including existing issues) ===\n\n''')
    with open(args.new) as new_report_details:
        pmd_summary_file.write(new_report_details.read())

# Export the summary file path.
env_path = os.getenv('GITHUB_ENV')
with open(env_path, 'a') as env_file:
    env_file.write(f'PMD_SUMMARY_FILE={pmd_summary_path}\n')
