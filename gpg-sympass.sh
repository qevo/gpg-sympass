#!/usr/bin/env bash

#===========================================================================
# GPG Symmetric Password Helper
#
# Use GPG to symmetrically encrypt or decrypt a single file or all files
# from a directory tree with a hash generated from an entered password.
#
# Features:
#   - AES 256-bit file encryption
#   - SHA 512-bit hash key generated from a password
#   - Output filename randomization
#   - Original filename stored in GPG packet
#   - Encrypt entire directories (recursive or not)
#   - Decrypt entire directories (recursive or not)
#
# Syntax:
#   gpg-sympass COMMAND [-h] [-k] [-z] [-r] [-o OUTPUT] INPUT
#
# Examples:
#   gpg-sympass encrypt file.txt
#   gpg-sympass decrypt file.txt.gpg
#   gpg-sympass encrypt /directory/file.txt
#   gpg-sympass decrypt /directory/file.txt.gpg
#   gpg-sympass encrypt -o ../encrypted/ directory/
#   gpg-sympass decrypt -o ../decrypted ../encrypted/
#===========================================================================

#
# Environment variables
#

# Make sure variables are not automatically exported
set +a

# Disable command history
set +o history

# Do not remember (hash) commands as they are looked up for execution
set +h

# Remove any set environment variable to guarantee it's not re-exported
gs_unset () {
    unset gs_script_name
    unset gs_arg_count
    unset gs_pass1
    unset gs_pass2
    unset gs_hash
    unset gs_command
    unset gs_keep_decrypt
    unset gs_input
    unset gs_output_file
    unset gs_output_dir
    unset gs_random_encrypt
    unset gs_recursive
    unset gs_debug
    unset -f gs_show_info_header
    unset -f gs_show_info_usage
    unset -f gs_show_info_note
    unset -f gs_show_debug
    unset -f gs_show_help
    unset -f gs_ensure_writable_path
    unset -f gs_write_encrypted_file
    unset -f gs_get_random_filename
    unset -f gs_encrypt_input_file
    unset -f gs_encrypt
    unset -f gs_get_decrypt_filename
    unset -f gs_decrypt_input_file
    unset -f gs_decrypt
}

gs_unset

#
# Script help and info
#

gs_show_info_header () {
    echo "GPG Symmetric Password Helper"
    echo "  Use GPG to symmetrically encrypt or decrypt a single file or all files"
    echo "  from a directory tree with a hash generated from an entered password."
}

gs_show_info_usage () {
    gs_script_name=$(readlink -f "${BASH_SOURCE[0]}")
    echo "  USAGE ${gs_script_name##*/} COMMAND [-h] [-k] [-z] [-r] [-o OUTPUT] INPUT"
}

gs_show_info_note () {
    echo "  Note:"
    echo "    Supplied password is hashed using SHA 512-bit."
    echo "    File encryption uses GnuPG with AES 256-bit cipher."
}

gs_show_help () {
    gs_show_info_header
    echo ""
    gs_show_info_note
    echo ""
    gs_show_info_usage
    echo ""
    echo "  COMMANDS"
    echo ""
    echo "    encrypt"
    echo "    decrypt"
    echo ""
    echo "  INPUT"
    echo ""
    echo "    If a file, the single file is processed."
    echo "    If a directory, all files in the directory are processed."
    echo "      If the [-r] flag is set, all files in the directory tree are processed."
    echo ""
    echo "  FLAGS"
    echo ""
    echo "    -h    Show help"
    echo ""
    echo "    -k    Keep decrypted file. (Default true)"
    echo "            If input and output are a file, explicit output filename will be used."
    echo "            Otherwise filename from --set-filename in GPG packet if available."
    echo "            Otherwise uses encrypted filename"
    echo "              - removes .gpg file ending if present"
    echo "              - removes .enc file ending if present"
    echo "            If decrypted filename already exists in the output directory, -decrypted" ##
    echo "               is appended to filename before the final suffix."
    echo ""
    echo "    -z    Randomize output filename (Default false)"
    echo "            Only relevant for ENCRYPT command."
    echo "            Set output filename(s) to a random 8 character alphanumeric string."
    echo ""
    echo "    -r    Recursive (Default false)"
    echo "            All files in the INPUT directory tree are processed."
    echo ""
    echo "    -o    Output filename or directory. (Default current working directory)"
    echo "            Directory path that does not exist must include a trailing slash."
    echo "            If a file, input must be a file."
    echo "            If a directory, that is where file(s) will be written."
    echo "            Filenames are preserved (eg file.txt.gpg) unless -z used."
}

gs_show_debug () {
    gs_show_info_header
    echo ""
    gs_show_info_usage
    echo ""
    echo "  DEBUG:"
    echo ""
    echo "    COMMAND   ${gs_command}"
    echo "    INPUT     ${gs_input}  [$(realpath ${gs_input})]"
    echo ""
    echo "    FLAGS"
    echo ""
    echo "      -k ${gs_keep_decrypt}"
    echo "      -z ${gs_random_encrypt}"
    echo "      -r ${gs_recursive}"
    echo "      -o ${gs_output_file}"
    echo ""
    echo "    INTERNALS"
    echo ""
    echo "      gs_output_dir ${gs_output_dir}  [$(realpath ${gs_output_dir})]"
}

#
# Script bootstrap
#

gs_arg_count=$#

# Check for help flag
for a in "${@}" ; do
    if [ "$a" == "-h" ] ; then
        gs_show_help
        gs_unset
        unset -f gs_unset
        exit
    fi
done

# Get and remove the first command line argument
gs_command="$1"
shift

# Get the last command line argument
for gs_input in "$@" ; do
    :
done

# Remove the last command line argument
set -- "${@:1:$(($#-1))}"

# Script defaults
gs_keep_decrypt="true"
gs_random_encrypt="false"
gs_recursive="false"
gs_debug="false"
gs_output_dir="./"

# Grab argument flags
while getopts ':o:k:zrd' arg; do
    case ${arg} in
        o) gs_output_file="${OPTARG}";;
        k) gs_keep_decrypt="${OPTARG}";;
        z) gs_random_encrypt="true";;
        r) gs_recursive="true";;
        d) gs_debug="true";;
        *) echo "Error: Illegal option -${OPTARG}"
           gs_unset
           unset -f gs_unset
           exit 1;;
    esac
done

# Show usage if no arguments passed in
if [ "${gs_arg_count}" -eq 0 ] ; then
    gs_show_help
    exit
fi

# Check for valid command
if [ "encrypt" != "${gs_command}" ] && [ "decrypt" != "${gs_command}" ] ; then
    echo "Error: Invalid command [${gs_command}]"
    gs_unset
    unset -f gs_unset
    exit 1
fi

# Check for any input
if [ -z "${gs_input}" ] ; then
    echo "Error: No input specified"
    gs_unset
    unset -f gs_unset
    exit 2
fi

# Check for valid input
if [ ! -d "${gs_input}" ] && [ ! -f "${gs_input}" ] ; then
    echo "Error: Input not valid [${gs_input}]"
    gs_unset
    unset -f gs_unset
    exit 3
fi

# Make sure input directory has a trailing slash for later
if [ -d "${gs_input}" ] && [ "/" != "${gs_input: -1}" ] ; then
    gs_input="${gs_input}/"
fi

# If output is a directory or has a trailing slash, set output dir
if [ -d "${gs_output_file}" ] || [ "/" = "${gs_output_file: -1}" ] ; then
    gs_output_dir=${gs_output_file}
    gs_output_file=
# If output is an absolute file path, split it and set output dir to avoid default relative
elif [ -f "${gs_output_file}" ] && [ "/" = "${gs_output_file:0:1}" ] ; then
    gs_output_dir="${gs_output_file%/*}"
    gs_output_file="${gs_output_file##*/}"
fi

# Make sure output directory has a trailing slash for later
if [ "/" != "${gs_output_dir: -1}" ] ; then
    gs_output_dir="${gs_output_dir}/"
fi

if [ "/" != "${gs_output_dir:0:1}" ] && [ "./" != "${gs_output_dir:0:2}" ] ; then
    gs_output_dir="./${gs_output_dir}"
fi

# Check for input and output mismatch
if [ "/" = "${gs_input: -1}" ] && [ ! -z "${gs_output_file}" ] ; then
#if [ -d "${gs_input}" ] && [ -f "${gs_output_file}" ] ; then
    echo "Error: Input directory cannot be written to a file"
    gs_unset
    unset -f gs_unset
    exit 4
fi

gs_ensure_writable_path () {
    local path="$1"
    local __resultvar="$2"
    local dir=
    local file=
    local funcOutput=
    local funcCode=0
    
    if [ -d "${path}" ] && [ -w "${path}" ] ; then
        funcOutput="${path}"
    
    elif [ -f "${path}" ] && [ -w "${path}" ] ; then
        funcOutput="${path}"
    
    else
        if [ "/" = "${path: -1}" ] ; then
            dir="${path}"
            file=
        else
            dir="${path%/*}"
            file="${path##*/}"
        fi
    
        if [ ! -z "${dir}" ] && [ ! -d "${dir}" ] ; then
            
            mkdir -p "${dir}"
            
            if [ "$?" -gt 0 ] ; then
                funcOutput="Error: Unable to create output directory [${dir}]"
                funcCode=1
            fi
        fi
    
        if [ ! -z "${file}" ] ; then
            
            touch "${path}"
            
            if [ "$?" -gt 0 ] ; then
            
                if [ ! -z "${dir}" ] ; then
                    
                    rmdir "${dir}"
                fi
                
                funcOutput="Error: Unable to write to file [${path}]"
                funcCode=2
            fi
        fi
    fi
    
    # Return the result
    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'$funcOutput'"
    else
        echo "${funcOutput}"
    fi
    
    return $funcCode
}

gs_write_encrypted_file () {
    local input_filename="$1"
    local hash="$2"
    local output_filename="$3"
    local __resultvar="$4"
    local input_abs_path=
    local funcOutput=
    local funcCode=0

    # Encrypt file
    funcOutput=$(gs_ensure_writable_path "${output_filename}")
    # If path not writable
    if [ $? -gt 0 ] ; then
        funcCode=1
    else
        funcOutput=$(gpg --quiet --cipher-algo AES256 --symmetric --passphrase "${hash}" --batch --yes --set-filename "${input_filename//\//\\}" --output "${output_filename}" "${input_filename}")
        if [ $? -gt 0 ] ; then funcCode=2; fi
    fi
    
    # Return the result
    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'$funcOutput'"
    else
        echo "${funcOutput}"
    fi
    
    return $funcCode
}

gs_get_random_filename () {
    local output_dir="$1"
    local __resultvar="$2"
    local funcOutput=
    local funcCode=0
    
    # bash generate random alphanumeric string
    filename=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
        
    # Check that output file does not already exist
    while [ -e "${output_dir}${filename}" ]; do
        # bash generate random alphanumeric string
        filename=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1)
    done
    
    funcOutput="${filename}"
    
    # Return the result
    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'$funcOutput'"
    else
        echo "${funcOutput}"
    fi
    
    return $funcCode
}

gs_encrypt_input_file () {
    local input_filename="$1"
    local hash="$2"
    local output_filename="$3"
    local output_dir="$4"
    local randomize_name="$5"
    local __resultvar="$6"
    local funcOutput=
    local funcCode=0
    
    # If no output filename, generate random
    if [ "${randomize_name}" = "true" ] ; then
        output_filename=$(gs_get_random_filename "${output_dir}")
    elif [ -z "${output_filename}" ] ; then
        output_filename="${input_filename##*/}.gpg"
    fi
    
    funcOutput=$(gs_write_encrypted_file "${input_filename}" "${hash}" "${output_dir}${output_filename}")
    
    if [ $? -eq 0 ] ; then
        funcOutput="${output_dir}${output_filename}"
    else
        funcOutput="Error: Failed to encrypt [${input_filename}]\n${funcOutput}"
        funcCode=1
    fi
    
    # Return the result
    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'$funcOutput'"
    else
        echo -e "${funcOutput}"
    fi
    
    return $funcCode
}

gs_encrypt () {
    local input="$1"
    local hash="$2"
    local output_filename="$3"
    local output_dir="$4"
    local randomize_name="$5"
    local recursive="$6"
    local __resultvar="$7"
    local funcOutput=
    local funcCode=0
    local tempRes=

    # If input is a file
    if [ -f "${input}" ] ; then
        
        funcOutput=$(gs_encrypt_input_file "${input}" "${hash}" "${output_filename}" "${output_dir}" "${randomize_name}")
        
        if [ $? -gt 0 ] ; then
            funcOutput="Error: Failed to encrypt [${input}]\n${funcOutput}"
            funcCode=1
        fi
        
    # If input is a directory
    elif [ -d "${input}" ] ; then

        if [ "${recursive}" = "true" ] ; then
            find "${input}"* -type f -print0 | while IFS= read -r -d $'\0' line; do
                if [ "./" = "${line:0:2}" ] ; then
                    line="${line:2}"
                fi
                tempRes=$(gs_encrypt_input_file "${line}" "${hash}" "${line}.gpg" "${output_dir}" "${randomize_name}")
                
                if [ $? -gt 0 ] ; then
                    echo -e "Error: Failed to encrypt [${line}]\n${tempRes}"
                    return 1
                else
                    echo "${tempRes}"
                fi
            done
        else
            find "${input}"* -prune -type f -printf "%p\0" | while IFS= read -r -d $'\0' line; do
                if [ "./" = "${line:0:2}" ] ; then
                    line="${line:2}"
                fi
                tempRes=$(gs_encrypt_input_file "${line}" "${hash}" "${line}.gpg" "${output_dir}" "${randomize_name}")
                
                if [ $? -gt 0 ] ; then
                    echo -e "Error: Failed to encrypt [${line}]\n${tempRes}"
                    return 1
                else
                    echo "${tempRes}"
                fi
            done
        fi
    fi
}

gs_get_decrypt_filename () {
    local input_filename="$1"
    local hash="$2"
    local output_filename="$3"
    local __resultvar="$4"
    local funcOutput=
    local funcCode=0
    local orig_name=
    
    # Use explicit output filename
    if [ ! -z "${output_filename}" ] ; then
        funcOutput="${output_filename}"
    else
        # Get filename from GPG packet
        orig_name=$(gpg --quiet --list-packets --batch --passphrase "${hash}" "${input_filename}" | grep -o -P "name=\"(.*)\"")
        
        orig_name="${orig_name#*\"}"
        orig_name="${orig_name%\"*}"
        
        if [ ! -z "${orig_name}" ] ; then
            funcOutput="${orig_name//\\//}"
        fi
    fi
    
    # Use input_filename when no other available
    if [ -z "${funcOutput}" ] ; then
        orig_name="${input_filename##*/}"
        
        # Remove .gpg and .enc
        while [ ".enc" = "${orig_name: -4}" ] || [ ".gpg" = "${orig_name: -4}" ] ; do
            orig_name="${orig_name%????}"
        done
        
        # Check that the file does not exist
        if [ ! -e "${orig_name}" ] ; then
            funcOutput="${orig_name}"
        else
            # Add -decrypted to file name
            if [ "${orig_name%.*}" = "${orig_name##*.}" ] ; then
                funcOutput="${orig_name}-decrypted"
            else
                funcOutput="${orig_name%.*}-decrypted${orig_name##*.}"
            fi
        fi
    fi
    
    # Return the result
    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'$funcOutput'"
    else
        echo "${funcOutput}"
    fi
    
    return $funcCode
}

gs_decrypt_input_file () {
    local input_filename="$1"
    local hash="$2"
    local keep="$3"
    local output_filename="$4"
    local output_dir="$5"
    local __resultvar="$6"
    local funcOutput=
    local funcCode
    
    if [ "${keep}" != "true" ] ; then
        funcOutput=$(gpg --batch --quiet --decrypt --passphrase "${hash}" "${input_filename}")
        if [ $? = 0 ] ; then # If GPG error
            funcOutput="Error: Failed to decrypt [${input_filename}]\n${funcOutput}"
            funcCode=2
        fi
    elif [ "${keep}" = "true" ] ; then
        output_filename=$(gs_get_decrypt_filename "${input_filename}" "${hash}" "${output_filename}")
        funcOutput=$(gs_ensure_writable_path "${output_dir}${output_filename}")
        # If path not writable
        if [ $? -gt 0 ] ; then funcCode=1;
        else
            funcOutput=$(gpg --batch --quiet --yes --decrypt --passphrase "${hash}" -o "${output_dir}${output_filename}" "${input_filename}")
            if [ $? -gt 0 ] ; then # If GPG error
                funcOutput="Error: Failed to decrypt [${input_filename}]\n${funcOutput}"
                funcCode=2
            else
                funcOutput="${output_dir}${output_filename}"
            fi
        fi
    fi
    
    # Return the result
    if [[ "$__resultvar" ]]; then
        eval $__resultvar="'$funcOutput'"
    else
        echo -e "${funcOutput}"
    fi
    
    return $funcCode
}

gs_decrypt () {
    local input="$1"
    local hash="$2"
    local keep="$3"
    local output_filename="$4"
    local output_dir="$5"
    local recurse="$6"
    local __resultvar="$7"
    local funcOutput=
    local funcCode=0
    local tempRes=
    
    # If input is a file
    if [ -f "${input}" ] ; then
    
        # Error if file not readable
        if [ ! -r "${input}" ] ; then
            funcOutput="Error: Cannot read file [${input}]"
            funcCode=1
        fi
    
        funcOutput=$(gs_decrypt_input_file "${input}" "${hash}" "${keep}" "${output_filename}" "${output_dir}")
        
        if [ $? -gt 0 ] ; then
            funcOutput="Error: Failed to decrypt [${input}]\n${funcOutput}"
            funcCode=2
        fi
        
    # If input is a directory
    elif [ -d "${input}" ] ; then

        if [ "${recurse}" = "true" ] ; then
            # For each file (recursive)
            find "${input}"* -type f -print0 | while IFS= read -r -d $'\0' line; do
                tempRes=$(gs_decrypt_input_file "${line}" "${hash}" "${keep}" "${output_filename}" "${output_dir}")
                if [ $? -gt 0 ] ; then
                    echo -e "Error: Failed to decrypt [${line}]\n${tempRes}"
                    return 1
                else
                    echo "${tempRes}"
                fi
            done
        else
            find "${input}"* -prune -type f -printf "%p\0" | while IFS= read -r -d $'\0' line; do
                tempRes=$(gs_decrypt_input_file "${line}" "${hash}" "${keep}" "${output_filename}" "${output_dir}")
                if [ $? -gt 0 ] ; then
                    echo -e "Error: Failed to decrypt [${line}]\n${tempRes}"
                    return 1
                else
                    echo "${tempRes}"
                fi
            done
        fi
    fi
}

if [ "${gs_debug}" = "true" ] ; then
    gs_show_debug
    gs_unset
    unset -f gs_unset
    exit
fi

# Read password from prompt
IFS= read -rs -p "Enter Password: " gs_pass1 < /dev/tty
echo ""
IFS= read -rs -p "Confirm Password: " gs_pass2 < /dev/tty
echo ""

if [ "${gs_pass1}" != "${gs_pass2}" ] ; then
    echo "Error: Password mismatch"
    gs_unset
    unset -f gs_unset
    exit 5
fi

# Turn password into a hash
gs_hash=$(printf "%s" "${gs_pass1}" | sha512sum | cut -d' ' -f1)

# Encrypt
if [ "encrypt" = "${gs_command}" ] ; then

    gs_encrypt "${gs_input}" "${gs_hash}" "${gs_output_file}" "${gs_output_dir}" "${gs_random_encrypt}" "${gs_recursive}"
    
#Decrypt
elif [ "decrypt" = "${gs_command}" ] ; then
    
    gs_decrypt "${gs_input}" "${gs_hash}" "${gs_keep_decrypt}" "${gs_output_file}" "${gs_output_dir}" "${gs_recursive}"
fi

gs_unset
unset -f gs_unset
