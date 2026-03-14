#!perl

use strict;
use warnings;

use Test::More tests => 2;
use Test::Warnings;

use CDB_File;

# Tying to a nonexistent file should fail gracefully without leaking memory.
# Before the fix, TIEHASH allocated a cdb struct but didn't free it when
# PerlIO_open failed.

my $result = tie(my %h, "CDB_File", "/nonexistent/path/to/file.cdb");
ok(!$result, "tie to nonexistent file returns false (no leak)");

note "exit";
exit;
