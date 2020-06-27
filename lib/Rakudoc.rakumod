# $?DISTRIBUTION.meta isn't defined yet, as of rakudo 2020.05.01.
constant VERSION = $?DISTRIBUTION.meta<version> // '0.2.0';
unit class Rakudoc:auth<github:Raku>:ver(VERSION):api<1>;

use Documentable::Primary;
use Pod::To::Text;
# Use our local version until development settles down; see Pod::From::Cache
#use Pod::Cache:ver($?DISTRIBUTION.meta<version>);  # Not ok in 2020.05.01
use Pod::Cache:ver(VERSION);

has $.cache;
has @!doc-source;
has @!extensions = <pod6 rakudoc pod p6 pm pm6>;
has $!verbose;

submethod TWEAK(:@doc-source is copy, :$!verbose, :$no-default-docs) {
    if !@doc-source and %*ENV<RAKUDOC> {
        @doc-source = %*ENV<RAKUDOC>.split(',').map(*.trim);
    }
    unless $no-default-docs {
        @doc-source.append: $*REPO.repo-chain.map({.?abspath.IO // Empty})».add('doc');
    }
    @!doc-source = grep *.d, map *.IO.resolve(:completely), @doc-source;
    $!cache = Pod::Cache.new: :cache-path<rakudoc-cache>;
}

class Rakudoc::Doc {
    has $.pod;
    has $.origin;

    method filename {
        given $.origin {
            when IO::Path { ~ .basename.IO.extension('', :parts(1)) }
            when CompUnit { .Str }
        }
    }
    method documentable {
        die join "\n",
                "Unexpected: doc pod '$.origin' has multiple elements:",
                |$.pod.pairs.map(*.raku)
            if $.pod.elems > 1;
        Documentable::Primary.new:
            :pod($.pod.first),
            :$.filename,
    }

    method Str { pod2text($!pod) }
}

method search-doc-dirs($fragment, :@extensions = @!extensions) {
    self!paths-for-fragment($fragment, :@extensions).map: {
        Rakudoc::Doc.new: :pod($!cache.pod(~ .absolute)), :origin($_);
    }
}

method search-compunits($module) {
    self!locate-curli-module($module).map: {
        Rakudoc::Doc.new: :pod($!cache.pod(.handle)), :origin($_);
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

method !locate-curli-module($short-name) {
    # TODO This is only the first one; keep on searching somehow?
    my $cu = try $*REPO.need(CompUnit::DependencySpecification.new: :$short-name);
    if $cu {
        note "- {$cu.repo.prefix} $cu" if $!verbose;
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
                    note "- '$path" if $!verbose;
                    push @paths, $path;
                    next DIR;
                }
            }
        }
    }

    @paths
}
