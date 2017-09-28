# BASH Templater
Very simple templating system that replace `{{VAR}}` by `$VAR` environment value
Supports default values by writting `{{VAR=value}}` in the template

## Author

Sébastien Lavoie <github@lavoie.sl>

Johan Haleby

See http://code.haleby.se/2015/11/20/simple-templating-engine-in-bash/  and http://blog.lavoie.sl/2012/11/simple-templating-system-using-bash.html for more details

## Usage


```sh
# Passing arguments directly
VAR=value templater.sh template

# Evaluate /tmp/foo and pass those variables to the template
# Useful for defining variables in a file
# Parentheses are important for not polluting the current shell
(set -a && . /tmp/foo && templater.sh template)

# A variant that does NOT pass current env variables to the templater
sh -c "set -a && . /tmp/foo && templater.sh template"


# Read variables from a file using the -f option:
templater.sh template -f variables.txt
```

`variables.txt`
```
# The author
AUTHOR=Johan
# The version
VERSION=1.2.3
```

Don't print any warning messages:

```sh
templater.sh template -f variables.txt -s
```


## Examples
See examples/
