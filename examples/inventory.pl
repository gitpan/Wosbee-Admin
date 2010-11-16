#!/usr/bin/perl -w
#
# getinventory.pl - Generate an inventory report of Wosbee web shop products
#                   to demonstrate Wosbee::Admin
#

use 5.010;
use Wosbee::Admin;
use Getopt::Std;

my %opts;
getopts('o:u:p:', \%opts);
unless ($opts{o} && $opts{u} && $opts{p}) {
    die "Usage: $0 -o organization -u username -p password\n";
} 

my $w = Wosbee::Admin->new(organization => $opts{o},
                                   user => $opts{u},
                               password => $opts{p});

my $p = $w->get_products_parsed;

for (sort keys %{$p}) {
    for (@{$p->{$_}->{PATH}}) {
        print ">> $_\n";
    }

    printf "   %-20s %-40.40s %5d\n", $_, $p->{$_}->{PRODUCT_NAME},
        ($p->{$_}->{PRODUCT_INSTOCK} // 0);
    foreach my $opt (keys %{ $p->{$_}->{PRODUCT_OPTIONS} }) {
        print "-- $opt\n";
        for (@{ $p->{$_}->{PRODUCT_OPTIONS}->{$opt} }) {
            printf "   %-20s %-40.40s %5d\n", $_->{code}, $_->{value}, 
                                              $_->{amount} // 0;
        }
    }
    print "(product hidden)\n" unless ($p->{$_}->{PRODUCT_VISIBLE});
    print "-" x 70, "\n";
}
