# GPG Symmetric Password Helper

Use GPG to symmetrically encrypt or decrypt a single file or all files
from a directory tree with a hash generated from an entered password.

## Features
* AES 256-bit file encryption
* SHA 512-bit hash key generated from a password
* Output filename randomization
* Input filename stored in GPG packet
* Encrypt entire directories (recursive or not)
* Decrypt entire directories (recursive or not)

## Syntax
gpg-sympass COMMAND [-h] [-k] [-z] [-r] [-o OUTPUT] INPUT

## Examples
```bash
gpg-sympass encrypt file.txt
gpg-sympass decrypt file.txt.gpg

gpg-sympass encrypt /directory/file.txt
gpg-sympass decrypt /directory/file.txt.gpg

gpg-sympass encrypt -o ../encrypted/ directory/
gpg-sympass decrypt -o ../decrypted ../encrypted/
```
