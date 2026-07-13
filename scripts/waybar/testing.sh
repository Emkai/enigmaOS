#!/bin/bash

TEST_VAR='<tt><span color=\"yellow\">testing</span></tt>\ntetetete'
#TEST_VAR="hej\ntetetete"

printf '{"text": "test", "tooltip":"%s"}' "$TEST_VAR"
