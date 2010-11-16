package Wosbee::Admin;
#
# Copyright 2010 Seestieto <http://seestieto.pl>
#
# This program is free software; you can redistribute it and/or modify it
# under the same terms as Perl itself.
#

=head1 NAME

Wosbee::Admin - Manage your Wosbee shop with ease

=head1 SYNOPSIS

  use Wosbee::Admin;
  $wb = Wosbee::Admin->new(organization => camelshop,
                           user         => merchant, 
                           password     => foobaz);

  print scalar $wb->filemanager_ls;
 
  $wb->filemanager_upload("stylesheet.css");
   
  my $p = $wb->get_products_parsed;
  for (sort keys %{$p}) {
      printf "%-20s %s\n", $_, $p->{$_}->{PRODUCT_NAME};
  }

=head1 DESCRIPTION

This module provides a management interface for Wosbee.com and
possibly other hosted web shop services running the Smilehouse
Workspace e-commerce software (tested with version 1.13). 

This module is mostly useful for the users of free-of-charge Wosbee 
service. If you need - and you most certainly will when your business
grows - anything more powerful, you'd be better off paying for
the enterprise hosting plan or running your own licensed copy
of the Workspace software with all the fancy integration features.
(Unless you decide to migrate to a free/libre e-commerce solution.)

The purpose of this module is just to make some simple day to day
tasks, such as uploading style sheet files or generating inventory
statements, little less painful.

B<Please note that this software is written by a third party and is NOT 
SUPPORTED by Smilehouse.> This software does not use any public APIs. 
Instead it emulates a human ("scraping"), and thus it WILL break when
Wosbee changes it's web interface. There is NO WARRANTY, to the
extent permitted by law. 

=cut

use strict;
use warnings;
use LWP::UserAgent;
use HTTP::Cookies;
use HTML::Form;
use HTML::TableExtract;
use Text::CSV::Encoded;
use Carp;

use vars qw($VERSION);
$VERSION = "0.01";

=head1 CONSTRUCTOR

=over 4

=item new(I<OPTIONS>)

Creates C<Wosbee::Admin> object. Logs into the web shop using the 
provided credentials: organization, user and password. 

By default, connects to the server L<https://admin.wosbee.com>. 
The optional named parameter "host" can be used to specify the 
URL of any other Smilehouse instance, or non-SSL connection.

=back

=cut

sub new {
    my $class = shift;

    my $self = bless {
        host => "https://admin.wosbee.com", 
        cwd => "/",
        @_
    }, $class;

    $self->{organization} || croak "Missing parameter: organization";
    $self->{user}         || croak "Missing parameter: user";
    $self->{password}     || croak "Missing parameter: password";

    $self->{ua} = LWP::UserAgent->new(),
    $self->{ua}->cookie_jar(HTTP::Cookies->new());
    push @{ $self->{ua}->requests_redirectable }, 'POST';

    # Login 
    # Note: This does not check if the login succeeds.
    my $r = $self->{ua}->post($self->{host} . "/Login",
                  { Organization => $self->{organization},
                    User         => $self->{user},
                    Password     => $self->{password},
                    Login        => " Login " });
    unless ($r->is_success) {
        croak $r->status_line;
    }
    my $form = HTML::Form->parse($r);
    $r = $self->{ua}->request($form->click);
    unless ($r->is_success) {
        croak $r->status_line;
    }

    $r->base =~ m:^(.*)/Index:;
    $self->{url} = $1;

    return $self;
}

=head1 METHODS

=over 4

=item get_products_csv()

Retrieve the product inventory and return a flat CSV string. This is the
raw CSV file from the Tools -E<gt> Export page without any processing, suitable
for manipulation with some spreadsheet program, or for backup purposes. 

If you want to process the data in Perl it most likely makes more sense to
use get_products_parsed().
    
Semicolon (;) is used as the separator and the data is UTF-8 encoded. 
The first line contains the headers. Refer to Workspace documentation
for explanation of the various fields.

=cut

sub get_products_csv {
    my $self = shift;
    # XXX: implement a way to select a product group.

    my $r = $self->{ua}->post("$self->{url}/Product_productExportSettings.do");

    my $form = HTML::Form->parse($r);

    # These are the default settings but set them explicitly just in case they 
    # will get changed in future versions

    $form->value('delim', ';');
    $form->value('encoding', 'UTF-8');

    $r = $self->{ua}->request($form->click);
    unless ($r->is_success) {
        croak $r->status_line;
    }

    # Step 2: accept "NNN products selected for download"
    $form = HTML::Form->parse($r);
    $r = $self->{ua}->request($form->click);
    unless ($r->is_success) {
        croak $r->status_line;
    }

    $r->content;
}


=item get_products_parsed()

Retrieve product inventory and parse it into a data structure. 

Returns a hashref, where the product itemcode is the key and the
value is a reference to records containing the different PRODUCT_* fields.  

Most of fields are provided as-is, but the PATH is split to
an array reference containing different path elements, and product
options are split like this:  

   'PRODUCT_OPTIONS' => {
      'Size' => [
        {
          'pricerule' => '',
          'amount' => '0',
          'value' => 'XS',
          'code' => '1234-BLK-XS'
        },
        {
          'pricerule' => '',
          'amount' => '3',
          'value' => 'S',
          'code' => '1234-WHT-S'
        },
      ]
    }

(As always, Data::Dumper is your friend.)

=cut

sub get_products_parsed {
    my $self = shift;

    my $data = $self->get_products_csv;

    my $csv = Text::CSV::Encoded->new({ sep_char => ';', encoding => 'utf8', binary => 1,
                                        blank_is_undef => 1 });

    open my $io, '<', \$data;  # getline_hr wants IO handle

    my @fields = split /;/, $io->getline;
    $csv->column_names(@fields);

    my %data;
    while (my $s = $csv->getline_hr($io)) {
        my $item = $s->{PRODUCT_ITEMCODE};
        delete $s->{PRODUCT_ITEMCODE};        

        # Split product options

        my $options = $s->{PRODUCT_OPTIONS};
        delete $s->{PRODUCT_OPTIONS};
        for my $optstr (split /\$\$/, $options) {
            my ($optname, $opts) = $optstr =~ /^([^:]*):(.*)$/;
            $optname =~ s/&#xF5;/:/g;  # Colon in option name is quoted as HTML entity
            my @o;
            for (split(/##/, $opts)) {
                my ($value, $pricerule, $code, $amount) = split /,/;
                push @o, { code => $code, pricerule => $pricerule, 
                          value => $value, amount => $amount };
            }
            $s->{PRODUCT_OPTIONS}->{$optname} = \@o;
        }

        # Split path

        $s->{PATH} = [ split /\@/, $s->{PATH} ];

        $data{$item} = $s;
    }
    $io->close;

    return \%data; 
}

=item filemanager_upload(I<FILE> [, I<DIR> ])

Upload a file using the File manager interface. The I<FILE> parameter
is a local file name. Unless the optional I<DIR> parameter is given,
the file is uploaded the root directory.

There is no filemanager_download method, since files can be downloaded
simply by accessing them with the normal web shop URL.

=cut

sub filemanager_upload {
    my $self = shift;
    my $file = shift;
    my $dir = shift;

    if ($dir) {
        $dir = "?dir=$dir";
    } else {
        $dir = "";
    }

    my $r = $self->{ua}->get("$self->{url}/P3303$dir");
    my $form = HTML::Form->parse($r);
    my $input = $form->find_input("pldr_fl", "file")
        or croak "Cannot find input field pldr_fl";
    $input->file($file);
    $form->value('pldr_ctn', 'pld');
    $form->enctype("multipart/form-data");
    $r = $self->{ua}->request($form->click("pldr_pldbtn"));
    1;
}


=item filemanager_upload_zip(I<ZIP>, [ I<DIR> ])

Upload a zip archive using the File manager interface. The I<ZIP>
parameter is a local file name. Unless the optional I<DIR> parameter
is given, the file is uploaded the root directory.

Beware that the zip file is extracted on the server and existing files
are overwritten.

=cut

sub filemanager_upload_zip {
    my $self = shift;
    my $zip = shift;
    my $dir = shift;

    if ($dir) {
        $dir = "?dir=$dir";
    } else {
        $dir = "";
    }

    my $r = $self->{ua}->get("$self->{url}/P3303$dir");
    my $form = HTML::Form->parse($r);
    my $input = $form->find_input("pldr_zip", "file")
        or croak "Cannot find input field pldr_zip";
    $input->file($zip);
    $form->value('pldr_ctn', 'zpld');
    $form->enctype("multipart/form-data");
    $r = $self->{ua}->request($form->click("pldr_zipbtn"));
    1;
}

=item filemanager_mkdir(I<DIR>)

Create a new directory using the File manager interface. Doesn't
work recursively; all directories in the given path, except for
the last one to be created, must already exist on the server.

=cut

sub filemanager_mkdir {
    my $self = shift;
    my $dir = shift;

    my $path = "";
    if ($dir =~ m:(.*)/(.*)$: ) {
        $path = $1;
        $dir = $2;
    }

    my $r = $self->{ua}->get("$self->{url}/P3303?dir=$path");
    my $form = HTML::Form->parse($r);
    $form->value('pldr_mkd', $dir);
    $form->value('pldr_ctn', 'mkd');
    $r = $self->{ua}->request($form->click("pldr_mkdbtn"));
    1;
}

=item filemanager_rm(I<FILE>)

Delete a file or directory using the File manager interface.

=cut

sub filemanager_rm {
    my $self = shift;
    my $file = shift;

    my $path = "";
    if ($file =~ m:(.*)/(.*)$: ) {
        $path = $1;
        $file = $2;
    }

    my $r = $self->{ua}->get("$self->{url}/P3303?dir=$path");
    my $form = HTML::Form->parse($r);
    $form->value('delparam', $file);
    $form->value('pldr_ctn', 'dlt');
    $r = $self->{ua}->request($form->click("pldr_mkdbtn"));
    1;
}

=item filemanager_ls([ I<PATH> ])

Get the directory listing using the File manager interface. In scalar context, return a 
multiline string somewhat similar to output of ls(1). In list context, return a list of 
hashrefs with the following keys: name, size, type, date. 

If no PATH is given, the root directory will be listed.

=cut

sub filemanager_ls {
    my $self = shift;
    my $dir = shift;

    my $r;
    if ($dir) {
        $r = $self->{ua}->get("$self->{url}/P3303?dir=$dir");
    } else {
        $r = $self->{ua}->get("$self->{url}/P3303");
    }
    my $te = HTML::TableExtract->new(slice_columns => 0,
                                     headers => 
                                     [ "Name", "Size", "Type", "Upload date" ]);
    my ($ts) = $te->parse($r->content);

    if (wantarray) {
        my @lsarray;
        for ($ts->rows) {
            next unless @$_[1];  # "up" link
            @$_[2] =~ s/ bytes//;
            push @lsarray, { name => @$_[1], size => @$_[2], 
                             type => @$_[3], date => @$_[4] };
        }
        return @lsarray;
    } else {
        my $str = "";
        for ($ts->rows) {
            next unless @$_[1];  # "up" link
            shift @$_;           # dir icon
            @$_[1] =~ s/ bytes//;
            $str .= sprintf  "%-40s %10d %-10s %s\n", @$_;
        }
        return $str;
    }
}

1;

__END__

=back

=head1 SECURITY CONSIDERATIONS

It's best to create a separate Workspace admin user account with limited 
access rights for using this module. If you just want to list your
inventory, grant the "Products management" access. If you're
going to do filemanager stuff, add "Outlook management". Currently
this module does not provide any functionality needing additional
rights.

In case you store the username and password hardcoded as clertext
in your scripts, please make sure they are not world readable.
It's a good idea to change the password from time to time. 

This module uses SSL by default. If you don't have SSLeay
(or other implementation) installed and are willing to take 
the risk, set the host parameter to http://admin.wosbee.com in new().

=head1 AUTHOR

Henrik Ahlgren E<lt>pablo@seestieto.plE<gt>

=head1 COPYRIGHT

Copyright 2010 Seestieto.

This library is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=cut
