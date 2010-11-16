#!perl -T

use Test::More tests => 1;

BEGIN {
    use_ok( 'Wosbee::Admin' ) || print "Bail out!
";
}

diag( "Testing Wosbee::Admin $Wosbee::Admin::VERSION, Perl $], $^X" );
