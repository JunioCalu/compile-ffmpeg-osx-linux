#!/bin/bash
find /usr/share/ffplayout/public/live -name "*.ts" -mmin +4 -exec rm -f {} \;
