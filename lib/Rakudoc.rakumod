# $?DISTRIBUTION.meta isn't defined during compilation, as of rakudo 2020.05.01
constant VERSION = $?DISTRIBUTION.meta<version> // '0.2.0';

unit class Rakudoc:auth<github:Raku>:ver(VERSION):api<1>;

use Documentable::Primary;
use Pod::To::Text;
# Use our local version until development settles down; see Pod::From::Cache
#use Pod::Cache:ver($?DISTRIBUTION.meta<version>);  # Not ok in 2020.05.01
use Pod::Cache:ver(VERSION);

has $.cache;
has @.doc-source;
has @.extensions = <pod6 rakudoc pod p6 pm pm6>;
has $.quiet;
has $.verbose;

my class X::Rakudoc::BadQuery is Exception {
    has $.query;
    method message { "Unrecognized query '$!query'" }
}

submethod TWEAK(:@doc-source is copy, :$!verbose, :$no-default-docs) {
    if !@doc-source and %*ENV<RAKUDOC> {
        @doc-source = %*ENV<RAKUDOC>.split(',').map(*.trim);
    }
    unless $no-default-docs {
        @doc-source.append:
            $*REPO.repo-chain.map({.?abspath.IO // Empty})».add('doc');
    }
    @!doc-source = grep *.d, map *.IO.resolve(:completely), @doc-source;
    $!cache = Pod::Cache.new: :cache-path<rakudoc-cache>;
}


role Rakudoc::Doc {
    has $.rakudoc;
    has $.origin;
    has $.def;

    has $!pod;

    submethod TWEAK {
        note "- ", self unless $!rakudoc.quiet;
    }

    method filename { ... }
    method pod { ... }

    method documentable {
        die join "\n",
                "Unexpected: doc pod '$.origin' has multiple elements:",
                |$.pod.pairs.map(*.raku)
            if $.pod.elems > 1;
        Documentable::Primary.new:
            :pod($.pod.first),
            :$.filename,
    }
    method Str {
        my $str;
        if $!def {
            my Documentable @secondaries;

            for $.documentable.defs -> $def {
                if $def.name eq $!def {
                    @secondaries.push($def);
                }
            }

            # Documentable is strict about Pod contents currently, and will
            # probably throw (X::Adhoc) for anything that isn't in the main
            # doc repo.
            # TODO Add more specific error handling & warning text
            CATCH { default { } }

            unless @secondaries {
                # TODO Add warning text — Where?
            }
            $str = @secondaries.map({pod2text(.pod)}).join("\n")
        }

        $str ||= .ends-with("\n") ?? $_ !! "$_\n" given pod2text($.pod)
    }
}

class Rakudoc::Doc::Path does Rakudoc::Doc {
    method gist {
        "Doc(*{$!origin.absolute})"
    }
    method filename {
        ~ $!origin.basename.IO.extension('', :parts(1))
    }
    method pod {
        $!pod //= $!rakudoc.cache.pod($!origin.absolute)
    }
}

class Rakudoc::Doc::File is Rakudoc::Doc::Path does Rakudoc::Doc {
    method gist {
        "Doc(*{$!origin.absolute})"
    }
    method pod {
        use Pod::Load;
        $!pod //= load($!origin.absolute)
    }
}

class Rakudoc::Doc::CompUnit does Rakudoc::Doc {
    method gist {
        "Doc({$!origin.repo.prefix} {$!origin})"
    }
    method filename {
        ~ $!origin
    }
    method pod {
        $!pod //= $!rakudoc.cache.pod($!origin.handle)
    }
}


role Rakudoc::Request {
    has $.rakudoc;
    has $.def;
    method search { ... }
}

class Rakudoc::Request::Module does Rakudoc::Request {
    has $.short-name;
    method search {
        die "Searching for a routine without a module name is not implemented yet"
            if not $!short-name;
        | $!rakudoc.search-doc-dirs(self),
        | $!rakudoc.search-compunits(self),
    }
}

class Rakudoc::Request::File does Rakudoc::Request {
    has $.file;
    method search {
        Rakudoc::Doc::File.new: :origin($!file.IO.resolve(:completely)), :$!rakudoc;
    }
}

method request(Str $query) {
    return Rakudoc::Request::File.new: :file($query.IO), :rakudoc(self)
        if $query.IO.e;

    grammar Rakudoc::Request::Grammar {
        token TOP { <module> <routine>? | <routine> }
        token module { <-[\s.]> + }
        token routine { '.' <( <-[\s.]> + )> }
    }

    Rakudoc::Request::Grammar.new.parse($query)
        or die X::Rakudoc::BadQuery.new: :$query;

    #note "PARSE: $/.raku()";
    return Rakudoc::Request::Module.new:
            :rakudoc(self), :short-name($/<module>), :def($/<routine>);
}

method search-doc-dirs($request, :@extensions = @!extensions) {
    self!paths-for-fragment(~$request.short-name, :@extensions).map: {
        Rakudoc::Doc::Path.new: :origin($_), :def($request.def), :rakudoc(self);
    }
}

method search-compunits($request) {
    self!locate-curli-module(~$request.short-name).map: {
        Rakudoc::Doc::CompUnit.new: :origin($_), :def($request.def), :rakudoc(self);
    }
}

method display(*@docs) {
    my $text = @docs.join("\n\n");;
    my $pager = $*OUT.t && [//] |%*ENV<RAKUDOC_PAGER PAGER>, 'more';
    if $pager {
        $pager = run :in, $pager;
        $pager.in.spurt($text, :close);
    }
    else {
        put $text;
    }
}

method build-index {
    die "NOT YET IMPLEMENTED";
}

method !locate-curli-module($short-name) {
    # TODO This is only the first one; keep on searching somehow?
    my $cu = try $*REPO.need(CompUnit::DependencySpecification.new: :$short-name);
    if $cu {
        list $cu;
    }
    else {
        Empty;
    }
}

method !paths-for-fragment($fragment is copy, :@extensions!) {
    return [$fragment.IO.resolve(:completely)] if $fragment.IO.is-absolute;

    my @paths;

    # Note: IO::Spec::Win32.splitdir splits on both '/' and '\', so
    # $fragment can be a Unixy or OS-specific path
    my @parts = $*SPEC.splitdir($fragment);

    for @!doc-source -> $dir {
        my @dirs = $dir.add: @parts[0];
        if @dirs[0].d {
            # Looks like user specified the Kind subdirectory they're
            # looking for; it's in @dirs now, so remove it from @parts
            $fragment = $*SPEC.catdir(@parts.skip).IO;
        }
        else {
            # Try all the subdirs
            my %sort = :Type(0), :Language(1);
            @dirs = $dir
                    .dir(:test({not .starts-with('.') and $dir.add($_).d}))
                    .sort({ %sort{$_.basename} // Inf });
        }
        @dirs ||= $dir;

        DIR: for @dirs -> $dir {
            for @extensions -> $ext {
                my $path = $dir.add($fragment).extension(:0parts, $ext);
                if $path.e {
                    push @paths, $path;
                    next DIR;
                }
            }
        }
    }

    @paths
}
