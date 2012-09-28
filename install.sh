#!/bin/bash
P=$(cd `dirname "${BASH_SOURCE[0]}"` && pwd)
cd $P
gem build ffmaplib.gemspec
gem install *.gem
rm -f *.gem
