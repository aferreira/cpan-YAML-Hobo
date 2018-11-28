
package YAML::Hobo;

# ABSTRACT: Poor man's YAML

BEGIN {
    require YAML::Tiny;
    YAML::Tiny->VERSION('1.70');
    our @ISA = qw(YAML::Tiny);
}

our @EXPORT_OK = qw(Dump Load);

use Data::Bool qw(true false);

sub Dump {
    return YAML::Hobo->new(@_)->_dump_string;
}

sub Load {
    my $self = YAML::Hobo->_load_string(@_);
    if (wantarray) {
        return @$self;
    }
    else {
        # To match YAML.pm, return the last document
        return $self->[-1];
    }
}

### Constants

# Printed form of the unprintable characters in the lowest range
# of ASCII characters, listed by ASCII ordinal position.
my @UNPRINTABLE = qw(
  0    x01  x02  x03  x04  x05  x06  a    b    t    n    v    f    r    x0E  x0F
  x10  x11  x12  x13  x14  x15  x16  x17  x18  x19  x1A  e    x1C  x1D  x1E  x1F
);

# These 3 values have special meaning when unquoted and using the
# default YAML schema. They need quotes if they are strings.
my %QUOTE = map { $_ => 1 } qw( null true false );

### Dumper functions

sub _dump_scalar {
    my $string = $_[1];
    my $is_key = $_[2];

    # Check this before checking length or it winds up looking like a string!
    my $has_string_flag = YAML::Tiny::_has_internal_string_value($string);
    return '~'  unless defined $string;
    return "''" unless length $string;
    if ( Scalar::Util::looks_like_number($string) ) {

        # keys and values that have been used as strings get quoted
        if ( $is_key || $has_string_flag ) {
            return qq|"$string"|;
        }
        else {
            return $string;
        }
    }
    if (   $string =~ /[\x00-\x09\x0b-\x0d\x0e-\x1f\x7f-\x9f\'\n\s]/
        or $QUOTE{$string} )
    {
        $string =~ s/\\/\\\\/g;
        $string =~ s/"/\\"/g;
        $string =~ s/\n/\\n/g;
        $string =~ s/[\x85]/\\N/g;
        $string =~ s/([\x00-\x1f])/\\$UNPRINTABLE[ord($1)]/g;
        $string =~ s/([\x7f-\x9f])/'\x' . sprintf("%X",ord($1))/ge;
        return qq|"$string"|;
    }
    if ( $string =~ /(?:^[~!@#%&*|>?:,'"`{}\[\]]|^-+$|:\z)/ ) {
        return "'$string'";
    }
    return $is_key ? $string : qq|"$string"|;
}

### Loader functions

my $re_capture_double_quoted = qr/\"([^\\"]*(?:\\.[^\\"]*)*)\"/;
my $re_capture_single_quoted = qr/\'([^\']*(?:\'\'[^\']*)*)\'/;
my $re_trailing_comment      = qr/(?:\s+\#.*)?/;

my $re_true  = qr/(?:y|Y|yes|Yes|YES|true|True|TRUE|on|On|ON)/;
my $re_false = qr/(?:n|N|no|No|NO|false|False|FALSE|off|Off|OFF)/;

# Load a YAML scalar string to the actual Perl scalar
sub _load_scalar {
    my ($self, $string, $indent, $lines) = @_;

    # Trim trailing whitespace
    $string =~ s/\s*\z//;

    # Explitic null/undef
    return undef if $string eq '~';

    # Booleans
    return true  if $string =~ /^$re_true\z/;
    return false if $string =~ /^$re_false\z/;

    # Single quote
    if ( $string =~ /^$re_capture_single_quoted$re_trailing_comment\z/ ) {
        return $self->_unquote_single($1);
    }

    # Double quote.
    if ( $string =~ /^$re_capture_double_quoted$re_trailing_comment\z/ ) {
        return $self->_unquote_double($1);
    }

    # Special cases
    if ( $string =~ /^[\'\"!&]/ ) {
        die \"YAML::Tiny does not support a feature in line '$string'";
    }
    return {} if $string =~ /^{}(?:\s+\#.*)?\z/;
    return [] if $string =~ /^\[\](?:\s+\#.*)?\z/;

    # Regular unquoted string
    if ( $string !~ /^[>|]/ ) {
        die \"YAML::Tiny found illegal characters in plain scalar: '$string'"
            if $string =~ /^(?:-(?:\s|$)|[\@\%\`])/ or
                $string =~ /:(?:\s|$)/;
        $string =~ s/\s+#.*\z//;
        return $string;
    }

    # Error
    die \"YAML::Tiny failed to find multi-line scalar content" unless @$lines;

    # Check the indent depth
    $lines->[0]   =~ /^(\s*)/;
    $indent->[-1] = length("$1");
    if ( defined $indent->[-2] and $indent->[-1] <= $indent->[-2] ) {
        die \"YAML::Tiny found bad indenting in line '$lines->[0]'";
    }

    # Pull the lines
    my @multiline = ();
    while ( @$lines ) {
        $lines->[0] =~ /^(\s*)/;
        last unless length($1) >= $indent->[-1];
        push @multiline, substr(shift(@$lines), $indent->[-1]);
    }

    my $j = (substr($string, 0, 1) eq '>') ? ' ' : "\n";
    my $t = (substr($string, 1, 1) eq '-') ? ''  : "\n";
    return join( $j, @multiline ) . $t;
}

1;

=encoding utf8

=head1 SYNOPSIS

    use YAML::Hobo;

    $yaml = YAML::Hobo::Dump(
        {   release => { dist => 'YAML::Tiny', version => '1.70' },
            author  => 'ETHER'
        }
    );

    # ---
    # author: "ETHER"
    # release:
    #   dist: "YAML::Tiny"
    #   version: "1.70"

=head1 DESCRIPTION

L<YAML::Hobo> is a module to read and write a limited subset of YAML.
It does two things: reads YAML from a string – with C<Dump> –
and dumps YAML into a string – via C<Load>.

Its only oddity is that, when dumping, it prefers double-quoted strings,
as illustrated in the L</SYNOPSIS>.

L<YAML::Hobo> is built on the top of L<YAML::Tiny>.
So it deals with the same YAML subset supported by L<YAML::Tiny>.

=head1 WHY?

The YAML specification requires a serializer to impose ordering
when dumping map pairs, which results in a "stable" generated output.

This module adds to this output normalization by insisting
on double-quoted string for values whenever possible.
This is meant to create a more familiar format avoiding
frequent switching among non-quoted text, double-quoted and single-quoted strings.

The intention is to create a dull homogeneous output,
a poor man's YAML, which is quite obvious and readable.

=head1 FUNCTIONS

=head2 Dump

    $string = Dump(list-of-Perl-data-structures);

Turns Perl data into YAML.

=head2 Load

    @data_structures = Load(string-containing-a-YAML-stream);

Turns YAML into Perl data.

=head1 CAVEAT

This module does not export any function.
But it declares C<Dump> and C<Load> as exportable.
That means you can use them fully-qualified – as C<YAML::Hobo::Dump>
and C<YAML::Hobo::Load> – or you can use an I<importer>, like
L<Importer> or L<Importer::Zim>. For example,

    use zim 'YAML::Hobo' => qw(Dump Load);

will make C<Dump> and C<Load> available to the code that follows.

=head1 SEE ALSO

L<YAML::Tiny>

=cut
