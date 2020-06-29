# $?DISTRIBUTION.meta isn't defined during compilation, as of rakudo 2020.05.01
constant VERSION = $?DISTRIBUTION.meta<version> // '0.2.0';

unit class Rakudoc:auth<github:Raku>:ver(VERSION):api<1>;

use Documentable::Primary;
use Pod::To::Text;
# Use our local version until development settles down; see Pod::From::Cache
#use Pod::Cache:ver($?DISTRIBUTION.meta<version>);  # Not ok in 2020.05.01
use Pod::Cache:ver(VERSION);

has $.data-dir is readonly;
has @.doc-source;
has @.extensions = <pod6 rakudoc pod p6 pm pm6>;
has $.quiet;
has $.verbose;

my class X::Rakudoc::BadQuery is Exception {
    has $.query;
    method message { "Unrecognized query '$!query'" }
}

submethod TWEAK(
    :@doc-source is copy,
    :$no-default-docs,
    :$data-dir,
    :$!verbose,
) {
    if !@doc-source and %*ENV<RAKUDOC> {
        @doc-source = %*ENV<RAKUDOC>.split(',').map(*.trim);
    }
    unless $no-default-docs {
        @doc-source.append:
            $*REPO.repo-chain.map({.?abspath.IO // Empty})».add('doc');
    }
    @!doc-source = grep *.d, map *.IO.resolve(:completely), @doc-source;

    $!data-dir = self!resolve-data-dir($data-dir // %*ENV<RAKUDOC_DATA>);
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

class Rakudoc::Doc::File does Rakudoc::Doc {
    method gist {
        "Doc(*{$!origin.absolute})"
    }
    method filename {
        ~ $!origin.basename.IO.extension('', :parts(1))
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
        die "Searching for a definition without a module name is not implemented yet"
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


method cache {
    state $cache;
    return $cache if $cache;
    $!data-dir.mkdir unless $!data-dir.d;
    $cache = Pod::Cache.new: :cache-path($!data-dir.add('cache'));
}

method request(Str $query) {
    return Rakudoc::Request::File.new: :file($query.IO), :rakudoc(self)
        if $query.IO.e;

    grammar Rakudoc::Request::Grammar {
        token TOP { <module> <definition>? | <definition> }
        token module { <-[\s.]> + }
        token definition { '.' <( <-[\s.]> + )> }
    }

    Rakudoc::Request::Grammar.new.parse($query)
        or die X::Rakudoc::BadQuery.new: :$query;

    #note "PARSE: $/.raku()";
    return Rakudoc::Request::Module.new:
            :rakudoc(self), :short-name($/<module>), :def($/<definition>);
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
        # TODO Use Shell::WordSplit or whatever is out there; for now this
        # makes a simple 'less -Fr' work
        $pager = run :in, |$pager.comb(/\S+/);
        $pager.in.spurt($text, :close);
    }
    else {
        put $text;
    }
}

method build-index {
    die "NOT YET IMPLEMENTED";
}

method !resolve-data-dir($data-dir) {
    # A major limitation is that currently there can only be a single
    # Pod::Cache instance in a program, due to how precompilation guts work.
    # This precludes having a read-only system-wide cache and a
    # user-writable fallback. So for now, each user must build & update
    # their own cache.
    # See https://github.com/finanalyst/raku-pod-from-cache/blob/master/t/50-multiple-instance.t

    return $data-dir.IO.resolve(:completely) if $data-dir;

    # By default, this will be ~/.cache/raku/rakudoc-data on most Unix
    # distributions, and ~\.raku\rakudoc-data on Windows and others
    my IO::Path @candidates = map *.add('rakudoc-data'),
        # Here is one way to get a system-wide cache: if all raku users are
        # able to write to the raku installation, then this would probably
        # work; of course, this will also require file locking to prevent
        # users racing against each other while updating the cache / indexes
        #$*REPO.repo-chain.map({.?prefix.?IO // Empty})
        #        .grep({ $_ ~~ :d & :w })
        #        .first(not *.absolute.starts-with($*HOME.absolute)),
        %*ENV<XDG_CACHE_HOME>.?IO.?add('raku') // Empty,
        %*ENV<XDG_CACHE_HOME>.?IO // Empty,
        $*HOME.add('.raku'),
        $*HOME.add('.perl6'),
        $*CWD;
        ;

    @candidates.first(*.f) // @candidates.first;
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
