#!/bin/bash

# Very simple templating system that replaces {{VAR}} with the value of $VAR.
# Supports default values by writing {{VAR=value}} inside the template file.
# Read values from a file using the same format; one {{VAR=value}} entry on each
# line.
#
# Any variable that has been set in the current environment will not be
# overwritten. This means that if you supply the value of a variable on the
# command line, this will ignore defaults in the template file, and also ignore
# any values provided by a config file.
#
# If variable values are provided by config file and not present in the
# enviroment, the defaults will also be ignored.

# Copyright (c) 2017 Sébastien Lavoie
# Copyright (c) 2017 Johan Haleby
# Copyright (c) 2017 Jody Foo
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

readonly PROGNAME=$(basename $0)
IFS=$'\n'

function usage {
    echo "Usage: ${PROGNAME} [-h] [-p] [-f <config file>] [-s] <template file>

    -h   Show this help text
    -p   Don't do anything, just print the result of the variable expansion(s)
    -f   Specify a file to read variables from
    -q   Don't print warning messages (for example if no variables are found)

Default values in the template file will be ignored if they are provided by the
config file. Both config file values and default values from the template will
be ignored if the variable is set in the environment.

Examples:
    VAR1=Something VAR2=1.2.3 ${PROGNAME} test.txt
    ${PROGNAME} -f my-variables.txt test.txt
    ${PROGNAME} -f my-variables.txt test.txt > new-test.txt"
}

# parse options
while getopts ":hpf:q" opt; do
    case $opt in
        h)
            usage
            exit 0
            ;;
        p)
            print_only="true"
            ;;
        f)
            if [[ ! -f "${OPTARG}" ]]; then
                echo "${PROGNAME}: config file '${OPTARG}' not found." >&2
                exit 1
            else
                config_file="${OPTARG}"
            fi
            ;;
        q)
            quiet="true"
            ;;
        \?)
            echo "${PROGNAME}: Invalid option -${OPTARG}." >&2
            exit 1
            ;;
        :)
            echo "${PROGNAME}: Option -${OPTARG} requires an argument." >&2
            exit 1
            ;;
    esac
done

# remove parsed options from $@
shift $((OPTIND-1))

# check for template file
if [ $# -eq 0 ]; then
    echo "${PROGNAME}: Please provide a template file." >&2
    usage
    exit 1
fi

# check that template file exists
template="${1}"
if [[ ! -f "${template}" ]]; then
    echo "${PROGNAME}: template file '${template}' not found." >&2
    exit 1
fi

# Extract variable names needed from template file to the variable $vars
vars=$(grep -oE '\{\{[A-Za-z0-9_]+\}\}' "${template}" | sort | uniq | sed -e 's/^{{//' -e 's/}}$//')
if [[ -z "$vars" && "$quiet" != "true" ]]; then
    echo "Warning: No variable was found in ${template}, syntax is {{VAR}}" >&2
fi

# Escape characters in a string
# $1: string to escape characters in
# All the following arguments are characters in the string to escape
# Example: escape "ab'\c" '\' "'"   ===>  ab\'\\c
function escape_chars {
    local content="${1}"
    shift

    for char in "$@"; do
        content="${content//${char}/\\${char}}"
    done

    echo "${content}"
}

# Create an escaped assignment expression.
# $1: name of variable
# $2: value of variable (characters \ and " will be escaped)
function echo_var {
    local var="${1}"
    local content="${2}"
    local escaped="$(escape_chars "${content}" "\\" '"')"

    echo "${var}=\"${escaped}\""
}

# Evaluate a variable assignment, e.g. HOME=blabla but check if the variable
# exists before evaluating the assignment (e.g. check if $HOME exists).
#
# Requires the assignment expression as its argument, e.g. HOME="blabla"
#
# Will assign a value to the variable $var as a side effect:
#   $var: name of variable in assignment
function eval_assignment_if_unset {
    local assignment_expression="${1}"
    var=$(echo "${assignment_expression}" | grep -oE "^[A-Za-z0-9_]+")

    # Eval assignment expression if the involved variable is unset. I.e. do not
    # override the existing value of the variable named by $var
    if [[ ! -n "${!var+x}" ]]; then
        eval "${assignment_expression}"
    fi
}

# Load variables from file if set. Assignments in the config_file use the same
# format as in the template file, i.e. lines containing VAR=VALUE
# All other lines will be ignored.
if [[ -n "${config_file+x}" ]]; then
    echo "Loading values from '${config_file}'..." >&2

    # Create temp file where & and "space" are escaped
    tmpfile=$(mktemp)
    sed -e "s/\&/\\\&/g" -e "s/\ /\\\ /g" "${config_file}" > $tmpfile

    # load assignments and run them if they do not conflict with an existing
    # variable.
    # Ignore all lines starting with a #
    ext_assignments=$(sed -e '/^#[A-Za-z0-9_]+/d' "${tmpfile}" | grep -oE '^[A-Za-z0-9_]+=.+$' "${tmpfile}")
    for ext_assignment in $ext_assignments; do
        eval_assignment_if_unset $ext_assignment
    done
fi

# Array of subtitutions to be used to process the $template file
declare -a replaces
replaces=()

# Read default values defined as {{VAR=value}} and delete those lines.
# They are evaluated, so you can do {{PATH=$HOME}} or {{PATH=`pwd`}}
# You can even reference variables previously defined in the template.
defaults=$(grep -oE '^\{\{[A-Za-z0-9_]+=.+\}\}$' "${template}" | sed -e 's/^{{//' -e 's/}}$//')
for default_assignment in $defaults; do
    # Eval the default assignment if the lefthand variable of the assignment is
    # not already set.
    eval_assignment_if_unset $default_assignment

    # remove define line
    replaces+=("-e")
    replaces+=("/^{{${var}=/d")

    # add the variable to the variables to be replaced
    vars="${vars} ${var}"
done

vars="$(echo "${vars}" | tr " " "\n" | sort | uniq)"

# Print list of value that will be used unless -q flag was used
if [[ "$quiet" != "true" ]]; then
    for var in $vars; do
        echo $(echo_var "${var}" "${!var}") >&2
    done
fi

# Quit after printing value list if option -p was used
if [[ "$print_only" == "true" ]]; then
    exit 0
fi

# Prepare replacements for occurrences of {{VAR}} in the template with the value
# of $VAR.
for var in $vars; do
    if [[ -n "${!var+x}" ]]; then
        # get value of variable in $var
        value="${!var}"
    else
        value=""
        if [[ $quiet != "true" ]]; then
            echo "Warning: The variable '$var' has no value." >&2
        fi
    fi

    # Escape slashes in $value
    value="$(escape_chars "${value}" "\\" '/' ' ')";

    # Create substitution expression that will replace {{VAR}} with the value of
    # $var
    replaces+=("-e")
    replaces+=("s/{{${var}}}/${value}/g")
done

sed "${replaces[@]}" "${template}"
