#!/usr/bin/perl -w                                         # -*- perl -*-

use strict;

use lib qw( ./lib );
use Config;
use File::Spec::Functions qw( catfile );
use Template;
use ExtUtils::MakeMaker;
use Template::Latex;
use Cwd;

select STDERR;
$| = 1;
select STDOUT;

our $QUIET  = 0;
our $ACCEPT = 0;
our $WIN32  = ($^O eq 'MSWin32');

#------------------------------------------------------------------------

message(<<EOF);

Template-Latex v$Template::Latex::VERSION
--------------------

The Template-Latex modules add LaTeX support for the Template Toolkit.

They allow you to create LaTeX documents using the full power of the
Template Toolkit.  The generated output can then be filtered through
the 'latex', 'pdflatex' and/or 'dvips' programs to create PDF, DVI and
PostScript documents.

To use the Template-Latex module you'll first need to install LaTeX on
your system and make sure the above programs are available.  Answer the
following questions to confirm their locations, then run 'make', 
'make test' and 'make install'.

EOF

#------------------------------------------------------------------------

our $LATEX    = ttprompt('latex path',    find_program($ENV{PATH}, "latex"));
our $PDFLATEX = ttprompt('pdflatex path', find_program($ENV{PATH}, "pdflatex"));
our $DVIPS    = ttprompt('dvips path',    find_program($ENV{PATH}, "dvips"));

fix_file(catfile('lib','Template','Latex.pm'), '$LATEX',    $LATEX);
fix_file(catfile('lib','Template','Latex.pm'), '$PDFLATEX', $PDFLATEX);
fix_file(catfile('lib','Template','Latex.pm'), '$DVIPS',    $DVIPS);

#------------------------------------------------------------------------

my %opts = (
    'NAME'	       => 'Template-Latex',
    'VERSION_FROM' => 'lib/Template/Latex.pm',
    'PMLIBDIRS'    => [ 'lib' ], 
    'PREREQ_PM'    => { 
        'Template'    => 2.15,
    },
    'dist'         => {
        'COMPRESS' => 'gzip',
        'SUFFIX'   => 'gz',
        'PREOP'    => 'bin/distfix -v -y',
    },
    'clean'        => {
        'FILES'    => join(' ', qw( t/output/test1.pdf 
                                    t/output/test1.ps 
                                    t/output/test1.dvi
                                    t/output/test2 
                                    t/output/test2.pdf 
                                    t/output/test2.ps 
                                    t/output/test2.dvi )),
    },
);

if ($ExtUtils::MakeMaker::VERSION >= 5.43) {
    $opts{ AUTHOR   } = 'Andy Wardley <abw@wardley.org>';
    $opts{ ABSTRACT } = 'Latex support for the Template Toolkit',
}

WriteMakefile(%opts);


#------------------------------------------------------------------------
# fix_file($file, $find, $fix)
#
# Fixes a variable definition in a file.  e.g. 
# fix_file('lib/Template/LaTex.pm', '$LATEX', '/path/to/latex')
#------------------------------------------------------------------------

sub fix_file {
    my ($file, $find, $fix) = @_;
    local *FP;
    local $/ = undef;

    $find = quotemeta($find);

    open(FP, "< $file") || die "$file: $!\n";
    my $text = <FP>;
    close(FP);

    ($text =~ s/^(\s*our\s*${find}\s*=\s*)'.*?'/$1'$fix'/m)
    	|| die "$find not found in $file\n";

    open(FP, "> $file") || die "$file: $!\n";
    print FP $text;
    close(FP);
}


#------------------------------------------------------------------------
# find_program($path, $prog)
#
# Find a program, $prog, by traversing the given directory path, $path.
# Returns full path if the program is found.
#
# Written by Craig Barratt, Richard Tietjen add fixes for Win32.
#
# abw changed name from studly caps findProgram() to find_program() :-)
#------------------------------------------------------------------------

sub find_program {
    my($path, $prog) = @_;

    foreach my $dir ( split($Config{path_sep}, $path) ) {
        my $file = File::Spec->catfile($dir, $prog);
        if ( !$WIN32 ) {
            return $file if ( -x $file );
        } else {
            # Windows executables end in .xxx, exe precedes .bat and .cmd
            foreach my $dx ( qw/exe bat cmd/ ) {
                return "$file.$dx" if ( -x "$file.$dx" );
            }
        }
    }
}


#------------------------------------------------------------------------
# message($text)
#
# Print message unless quiet mode.
#------------------------------------------------------------------------

sub message {
    return if $QUIET;
    print @_;
}


#------------------------------------------------------------------------
# ttprompt($message, $default)
#------------------------------------------------------------------------

sub ttprompt {
    my ($msg, $def)=@_;
    my $ISA_TTY = -t STDIN && (-t STDOUT || !(-f STDOUT || -c STDOUT)) ; # Pipe?
    my $dispdef = defined $def ? "[$def] " : " ";
    $def = defined $def ? $def : "";
    my $ans = '';
    local $|=1;
    print "$msg $dispdef" unless $QUIET;
    if ($ACCEPT || ! $ISA_TTY) {
        print "$def\n" unless $QUIET;
    }
    else {
        chomp($ans = <STDIN>);
    }
    return ($ans ne '') ? $ans : $def;
}


