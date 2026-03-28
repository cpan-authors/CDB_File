#!perl

use strict;
use warnings;

use FindBin;
use lib "$FindBin::Bin/lib";
use Helpers;

use Test::More tests => 5;
use Test::Warnings;

use CDB_File;

# Test 1: DESTROY without finish() should clean up the temp file
{
    my ( $db, $db_tmp ) = get_db_file_pair(1);
    my $db_file  = $db->filename;
    my $tmp_file = $db_tmp->filename;

    {
        my $t = CDB_File->new( $db_file, $tmp_file ) or die "Failed to create cdb: $!";
        $t->insert( 'key1', 'value1' );
        $t->insert( 'key2', 'value2' );
        # Let $t go out of scope without calling finish()
    }

    ok( !-e $tmp_file, "Temp file cleaned up when DESTROY called without finish()" );
    ok( !-e $db_file,  "Final file not created when finish() not called" );
}

# Test 2: DESTROY after finish() should not unlink the final file
{
    my ( $db, $db_tmp ) = get_db_file_pair(1);
    my $db_file  = $db->filename;
    my $tmp_file = $db_tmp->filename;

    {
        my $t = CDB_File->new( $db_file, $tmp_file ) or die "Failed to create cdb: $!";
        $t->insert( 'key1', 'value1' );
        $t->finish or die "finish failed";
    }

    ok( -e $db_file,   "Final file exists after finish() + DESTROY" );
    ok( !-e $tmp_file, "Temp file gone after finish() (renamed to final)" );
    unlink $db_file;
}

note "exit";
exit;
