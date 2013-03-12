#!/bin/sh

# This script replaces sensitive information in autobuild.sh

sed -i 's/^repdir=.*/repdir=\[dir\]/g' autobuild.sh
sed -i 's/^repnms=.*/repnms=\[name\]/g' autobuild.sh
sed -i 's/^rmuser=.*/rmuser=\[user\]/g' autobuild.sh
sed -i 's/^rmhost=.*/rmhost=\[host\]/g' autobuild.sh
sed -i 's/^rmport=.*/rmport=\[port\]/g' autobuild.sh
sed -i 's/^rmpath=.*/rmport=\[path\]/g' autobuild.sh
