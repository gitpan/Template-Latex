#============================================================= -*-perl-*-
#
# Template::Latex
#
# DESCRIPTION
#   Provides an interface to Latex from the Template Toolkit.
#
# AUTHOR
#   Andy Wardley   <abw@wardley.org>
#
# COPYRIGHT
#   Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.
#
#   This module is free software; you can redistribute it and/or
#   modify it under the same terms as Perl itself.
#
# HISTORY
#   * Latex plugin originally written by Craig Barratt, Apr 28 2001.
#   * Win32 additions by Richard Tietjen.
#   * Extracted into a separate Template::Latex module by Andy Wardley,
#     May 2006
#
#========================================================================
 
package Template::Latex;

use strict;
use warnings;
use base 'Template';
use Template::Exception;
use File::Path;
use File::Spec;
use Cwd;

our $VERSION  = 2.16;
our $DEBUG    = 0 unless defined $DEBUG;
our $ERROR    = '';
our $FILTER   = 'latex';        # default filter name
our $THROW    = 'latex';        # exception type
our $DIR      = 'tt2latex';     # temporary directory name
our $DOC      = 'tt2latex';     # temporary file name
our $FORMAT   = '';             # output format (auto-detect if unset)
our $FORMATS  = {               # valid output formats and program alias
    pdf => 'pdflatex',
    ps  => 'latex',
    dvi => 'latex',
};

# LaTeX executable paths set at installation time by the Makefile.PL
our $LATEX    = '';
our $PDFLATEX = '';
our $DVIPS    = '';


sub new {
    my $class  = shift;
    my $config = @_ && ref $_[0] eq 'HASH' ? shift : { @_ };
    my $self   = $class->SUPER::new($config) || return;

    # set default format from config option
    $self->latex_format($config->{ LATEX_FORMAT })
        if $config->{ LATEX_FORMAT };

    # set latex paths from config options
    $self->latex_paths({
        latex    => $config->{ LATEX_PATH    },
        pdflatex => $config->{ PDFLATEX_PATH },
        dvips    => $config->{ DVIPD_PATH    },
    });

    # install the latex filter
    $self->define_filter( $self->context() );

    return $self;
}


#------------------------------------------------------------------------
# latex_format()
# latex_path()
# pdflatex_path()
# dvips_path()
#
# Methods to get/set the $FORMAT, $LATEX, $PDFLATEX and $DVIPS package
# variables that specify the default output format and the paths to
# the latex, pdflatex and dvips programs.
#------------------------------------------------------------------------

sub latex_format {
    my $class = shift;
    return @_ ? ($FORMAT = shift) : $FORMAT;
}

sub latex_path {
    my $class = shift;
    return @_ ? ($LATEX = shift) : $LATEX;
}

sub pdflatex_path {
    my $class = shift;
    return @_ ? ($PDFLATEX = shift) : $PDFLATEX;
}

sub dvips_path {
    my $class = shift;
    return @_ ? ($DVIPS = shift) : $DVIPS;
}


#------------------------------------------------------------------------
# latex_paths()
#
# Method to get/set the above all in one go.
#------------------------------------------------------------------------

sub latex_paths {
    my $class = shift;
    if (@_) {
        my $args = ref $_[0] eq 'HASH' ? shift : { @_ };
        $class->latex_path($args->{ latex }) 
            if defined $args->{ latex };
        $class->pdflatex_path($args->{ pdflatex }) 
            if defined $args->{ pdflatex };
        $class->dvips_path($args->{ dvips }) 
            if defined $args->{ dvips };
    }
    else {
        return {
            latex    => $LATEX,
            pdflatex => $PDFLATEX,
            dvips    => $DVIPS,
        } 
    }
}


#------------------------------------------------------------------------
# define_filter($context, $config)
#
# This method defines the latex filter in the context specified as the 
# first argument.  A list or hash ref of named parameters can follow
# providing default configuration options.  
#------------------------------------------------------------------------

sub define_filter {
    my $class   = shift;
    my $context = shift;
    my $default = @_ && ref $_[0] eq 'HASH' ? shift : { @_ };
    my $filter  = $default->{ filter } || $FILTER;

    # default any config item not set to values in package variables
    $default->{ format   } ||= $FORMAT;
    $default->{ latex    } ||= $LATEX;
    $default->{ pdflatex } ||= $PDFLATEX;
    $default->{ dvips    } ||= $DVIPS;

    # define a factory subroutine to be called when the filter is used.
    my $factory = sub { 
        my $context = shift;
        my $config  = @_ && ref $_[0] eq 'HASH' ? pop : { };

        # merge any configuration parameters specified when the filter
        # is used with the defaults provided when the filter was defined
        $config->{ $_ } ||= $default->{ $_ } 
            for (qw( format latex pdflatex dvips ));

        # output file can be specified as the first argument
        $config->{ output } = shift if @_;

        # return an anonymous filter subroutine which calls the real
        # filter() method passing the context and merged config params
        return sub {
            filter(shift, $context, $config);
        };
    };

    # install the filter factory in the context
    $context->define_filter( $filter => $factory, 1 );
}


#------------------------------------------------------------------------
# filter($text, $context, $config)
#
# The main Latex filter subroutine.
#------------------------------------------------------------------------

sub filter {
    my $text    = shift;
    my $context = shift;
    my $config  = @_ && ref $_[0] eq 'HASH' ? shift : { @_ };
    my $null    = File::Spec->devnull();
    my $tmp     = File::Spec->tmpdir();
    my $cwd     = cwd();
    my $n       = 0;
    my ($dir, $file, $data, $path, $dest, $ok);
    local(*FH);

    # check we're running on a supported OS 
    throw("not available on $^O")
        if $^O =~ /^(MacOS|os2|VMS)$/i;

    my $output = $config->{ output };
    my $format = $config->{ format };
    my $progname;

    if ($format) {
        $progname = $FORMATS->{ lc $format }
            || throw("invalid output format: $format");
    }
    else {
        # if the format isn't specified then we auto-detect it from the
        # extension of the output filename or look to see if the output
        # filename indicates the format to support old-skool usage, 
        # e.g. FILTER latex('pdf')

        throw('output format not specified')
            unless defined $output;

        if ($output =~ /\.(\w+)$/) {
            $format   = $1;
            $progname = $FORMATS->{ lc $format }
                || throw("invalid output format: $format");
        }
        elsif ($progname = $FORMATS->{ lc $output }) {
            $format = $output;
            $output = undef;
        }
        else {
            throw("cannot determine output format from file name: $output");
        }
    }

    # get the full path to the executable for this output format
    my $program = $config->{ $progname }
        || throw("$progname cannot be found, please specify its location");

    # we also need dvips as the second stage for 'ps' output
    my $dvips = $config->{ dvips }
        || throw("dvips cannot be found, please specify its location")
            if $format eq 'ps';

    # create a temporary directory 
    do { 
        $dir = File::Spec->catdir($tmp, "$DIR$$" . '_' . $n++);
    } while (-e $dir);
    eval { mkpath($dir, 0, 0700) };
    throw("failed to create temporary directory: $@") 
        if $@;

    # chdir to tmp dir - latex must run there
    unless (chdir($dir) ) {
        rmtree($dir);
        throw("failed to chdir to $dir: $!");
    }

    # open .tex file for output
    $file = File::Spec->catfile($dir, "$DOC.tex");
    unless (open(FH, ">$file")) {
        rmtree($dir);
        throw("failed to open $file for output: $!");
    }
    print(FH $text);
    close(FH);

    # quote backslashes except on MSWin32 which doesn't need it
    my $args = "\\nonstopmode\\input{$DOC}";
    $args = "'$args'" unless $^O eq 'MSWin32';

    # generate a command to run the program
    my $cmd = "$program $args 1>$null 2>$null 0<$null";

    if ($DEBUG) {
        debug( "output: ", ($output || '<none>'), "\n" );
        debug( "format: $format\n" );
        debug( "progname: $progname\n" );
        debug( "program: $program\n" );
        debug( "dir: $dir\n" );
        debug( "file: $file\n" );
        debug( "cmd: $cmd\n"  );
    }

    if (system($cmd)) {
        # an error occurred so we attempt to extract the interesting lines
        # from the log file
        my $errors = "";
        $file = File::Spec->catfile($dir, "$DOC.log");

        if (open(FH, "<$file") ) {
            my $matched = 0;
            while ( <FH> ) {
                # TeX errors start with a "!" at the start of the
                # line, and followed several lines later by a line
                # designator of the form "l.nnn" where nnn is the line
                # number.  We make sure we pick up every /^!/ line,
                # and the first /^l.\d/ line after each /^!/ line.
                if ( /^(!.*)/ ) {
                    $errors .= $1 . "\n";
                    $matched = 1;
                }
                if ( $matched && /^(l\.\d.*)/ ) {
                    $errors .= $1 . "\n";
                    $matched = 0;
                }
            }
            close(FH);
        } 
        else {
            $errors = "failed to open $file for input";
        }
        $ok = chdir($cwd);
        rmtree($dir);
        throw("failed to chdir to $cwd: $!") unless $ok;
        throw("$progname exited with errors:\n$errors");
    }

    if ($dvips) {
        # call dvips (if set) to generate PostScript output
        $file = File::Spec->catfile($dir, "$DOC.dvi");
        $cmd  = "$dvips $DOC -o 1>$null 2>$null 0<$null";

        if (system($cmd)) {
            $ok = chdir($cwd);
            rmtree($dir);
            throw("failed to chdir to $cwd: $!") unless $ok;
            throw("$dvips $file failed");
        }
    }

    # chdir back to where we started from
    unless (chdir($cwd)) {
        rmtree($dir);
        throw("failed to chdir to $cwd: $!");
    }

    # construct file name of the generated document
    $file = File::Spec->catfile($dir, "$DOC.$format");

    if ($output) {
        $path = $context->config->{ OUTPUT_PATH }
            || throw('OUTPUT_PATH is not set');
        $dest = File::Spec->catfile($path, $output);

        # see if we can rename the generate file to the desired output 
        # file - this may fail, e.g. across filesystem boundaries (and
        # it's quite common for /tmp to be a separate filesystem
        if (rename($file, $dest)) {
            debug("renamed $file to $dest") if $DEBUG;
            # success!  clean up and return nothing much at all
            rmtree($dir);
            return '';
        }
    }

    # either we can't rename the file or the user hasn't specified
    # an output file, so we load the generated document into memory
    unless (open(FH, $file)) {
        rmtree($dir);
        throw("failed to open $file for input ($dir)");
    }
    local $/ = undef;       # slurp file in one go
    binmode(FH);
    $data = <FH>;
    close(FH);

    # cleanup the temporary directory we created
    rmtree($dir);

    # write the document back out to any destination file specified
    if ($output) {
        debug("writing output to $dest\n") if $DEBUG;
        my $error = Template::_output($dest, \$data, { binmode => 1 });
        throw($error) if $error;
        return '';
    }

    debug("returning ", length($data), " bytes of document data\n")
        if $DEBUG;

    # or just return the data
    return $data;
}


#------------------------------------------------------------------------
# throw($error)
#
# Throw an error message as a Template::Exception.
#------------------------------------------------------------------------

sub throw {
    die Template::Exception->new( $THROW => join('', @_) );
}

sub debug {
    print STDERR "[latex] ", @_;
}


1;

__END__

=head1 NAME

Template::Latex - Latex support for the Template Toolkit

=head1 SYNOPSIS

    use Template::Latex;
    
    my $tt = Template::Latex->new({
        INCLUDE_PATH  => '/path/to/templates',
        OUTPUT_PATH   => '/path/to/pdf/output',
        LATEX_FORMAT  => 'pdf',
    });
    my $vars = {
        title => 'Hello World',
    }
    $tt->process('example.tt2', $vars, 'example.pdf', binmode => 1)
        || die $tt->error();

=head1 DESCRIPTION

The Template::Latex module is a wrapper of convenience around the
Template module, providing additional support for generating PDF,
PostScript and DVI documents from LaTeX templates.

You use the Template::Latex module exactly as you would the Template
module.  

    my $tt = Template::Latex->new(\%config);
    $tt->process($input, \%vars, $output)
        || die $t->error();

It supports a number of additional configuration parameters. The
C<LATEX_PATH>, C<PDFLATEX_PATH> and C<DVIPS_PATH> options can be used
to specify the paths to the F<latex>, F<pdflatex> and F<dvips> program
on your system, respectively.  These are usually hard-coded in the
Template::Latex C<$LATEX>, C<$PDFLATEX> and C<$DVIPS> package
variables based on the values set when you run C<perl Makefile.PL> to
configure Template::Latex at installation time.  You only need to
specify these paths if they've moved since you installed
Template::Latex or if you want to use different versions for some
reason.

    my $tt = Template::Latex->new({
        LATEX_PATH    => '/usr/bin/latex',
        PDFLATEX_PATH => '/usr/bin/pdflatex',
        DVIPS_PATH    => '/usr/bin/dvips',
    });

It also provides the C<LATEX_FORMAT> option to specify the default
output format.  This can be set to C<pdf>, C<ps> or C<dvi>.

    my $tt = Template::Latex->new({
        LATEX_FORMAT  => 'pdf',
    });

The C<latex> filter is automatically defined when you use the
Template::Latex module.  There's no need to load the Latex plugin in
this case, although you can if you want (e.g. to set some
configuration defaults).  If you're using the regular Template module
then you should first load the Latex plugin to define the C<latex>
filter.

    [% USE Latex %]
    [% FILTER latex('example.pdf') %]
    ...LaTeX doc...
    [% END %]

=head1 PUBLIC METHODS

The Template::Latex module is a subclass of the Template module and
inherits all its methods.  Please consult the documentation for the
L<Template> module for further information on using it for template
processing.  Wherever you see C<Template> substitute it for
C<Template::Latex>.

In addition to those inherted from the Template module, the following
methods are also defined.

=head2 latex_paths()

Method to get or set the paths to the F<latex>, F<pdflatex> and
F<dvips> programs.  These values are stored in the Template::Latex
C<$LATEX>, C<$PDFLATEX> and C<$DVIPS> package variables, respectively.
It can be called as either a class or object method.

    Template::Latex->latex_paths({
        latex    => '/usr/bin/latex',
        pdflatex => '/usr/bin/pdflatex',
        dvips    => '/usr/bin/dvips',
    });

    my $paths = Template::Latex->latex_paths();
    print $paths->{ latex };    # /usr/bin/latex

=head2 latex_path()

Method to get or set the C<$Template::Latex::LATEX> package
variable which defines the location of the F<latex> program on your
system.  It can be called as a class or object method.

    Template::Latex->latex_path('/usr/bin/latex');
    print Template::Latex->latex_path();   # '/usr/bin/latex'

=head2 pdflatex_path()

Method to get or set the C<$Template::Latex::PDFLATEX> package
variable which defines the location of the F<pdflatex> program on your
system.  It can be called as a class or object method.

    Template::Latex->pdflatex_path('/usr/bin/pdflatex');
    print Template::Latex->pdflatex_path();   # '/usr/bin/pdflatex'

=head2 dvips_path()

Method to get or set the C<$Template::Latex::DVIPS> package
variable which defines the location of the F<dvips> program on your
system.  It can be called as a class or object method.

    Template::Latex->dvips_path('/usr/bin/dvips');
    print Template::Latex->dvips_path();   # '/usr/bin/dvips'

=head1 INTERNALS

This section is aimed at a technical audience.  It documents the
internal methods and subroutines as a reference for the module's
developers, maintainers and anyone interesting in understanding how it
works.  You don't need to know anything about them to use the module
and can safely skip this section.

=head2 define_filter($context,\%config)

This class method installs the C<latex> filter in the context passed
as the first argument.  The second argument is a hash reference
containing any default filter parameters (e.g. those specified when
the Template::Plugin::Latex plugin is loaded via a C<USE> directive).

    Template::Latex->define_filter($context, { format => 'pdf' });

The filter is installed as a I<dynamic filter factory>.  This is just
a fancy way of saying that the filter generates a new filter
subroutine each time it is used to account for different invocation
parameters.  The filter subroutine it creates is effectively a wrapper
(a "closure" in technical terms) around the C<filter()> subroutine
(see below) which does the real work.  The closure keeps track of any
configuration parameters specified when the filter is first defined
and/or when the filter is invoked.  It passes the merged configuration
as the second argument to the C<filter()> subroutine (see below).

See the L<Template::Filters> module for further information on how
filters work.

=head2 filter($text,\%config)

This is the main LaTeX filter subroutine which is called by the
Template Toolkit to generate a LaTeX document from the text passed as
the first argument.  The second argument is a reference to a hash
array of configuration parameters.  These are usually provided by the
filter subroutine that is generated by the filter factory.

    Template::Latex::filter($latex, { 
        latex    => '/usr/bin/latex',
        pdflatex => '/usr/bin/pdflatex',
        dvips    => '/usr/bin/dvips',
        output   => 'example.pdf',
    });

=head2 throw($message)

Subroutine which throws a L<Template::Exception> error using C<die>.
The exception type is set to C<latex>.

    Template::Latex::throw("I'm sorry Dave, I can't do that");

=head2 debug($message)

Debugging subroutine which print all argument to STDERR.  Set the 
C<$DEBUG> package variable to enable debugging messages.

    $Template::Latex::DEBUG = 1;

=head1 AUTHOR

Andy Wardley E<lt>abw@wardley.orgE<gt> L<http://wardley.org/>

The original Latex plugin on which this is based was written by Craig
Barratt with additions for Win32 by Richard Tietjen.

=head1 COPYRIGHT

Copyright (C) 1996-2006 Andy Wardley.  All Rights Reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself.

=head1 SEE ALSO

L<Template::Plugin::Latex>

=cut

# Local Variables:
# mode: perl
# perl-indent-level: 4
# indent-tabs-mode: nil
# End:
#
# vim: expandtab shiftwidth=4:
