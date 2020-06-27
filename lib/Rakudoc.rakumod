unit class Rakudoc:auth<github:Raku>:ver<0.2.0>:api<1>;

use Documentable::Primary;
use Pod::To::Text;
# Use our local version until development settles down; see Pod::From::Cache
use Pod::Cache;

has $.cache;
has @!doc-source;
has @!extensions = <pod6 rakudoc pod p6 pm pm6>;
has $!verbose;

submethod TWEAK(:@doc-source is copy, :$!verbose) {
    if !@doc-source and %*ENV<RAKUDOC> {
        @doc-source = %*ENV<RAKUDOC>.split(',').map(*.trim);
    }
    @!doc-source = grep *.d, map {
            $_ eq ':DEFAULT'
                ?? | $*REPO.repo-chain.map({.?abspath.IO // Empty})».add('doc')
                !! .IO.resolve(:completely)
        }, @doc-source || ':DEFAULT';
    $!cache = Pod::Cache.new: :cache-path<rakudoc-cache>;
}

method get-it($fragment, :@extensions = @!extensions) {
    if self!paths-for-fragment($fragment, :@extensions) -> @paths {
        @paths.map: {
            my $pod = $!cache.pod: .absolute;
            die join "\n",
                    "Unexpected: doc pod has multiple elements:",
                    |$pod.pairs.map(*.raku)
                unless $pod.elems == 1;
            Documentable::Primary.new(
                :pod($pod.first),
                :filename(~ .basename.IO.extension('', :parts(1))),
            )
        };
    }
    else {
        die "NYI parse '$fragment' & locate module";
    }
}

method show-it($docs) {
    my $text = $docs.map({ pod2text(.pod) }).join("\n\n");;
    my $pager = $*OUT.t && [//] |%*ENV<RAKUDOC_PAGER PAGER>, 'more';
    if $pager {
        $pager = run :in, $pager;
        $pager.in.spurt($text, :close);
    }
    else {
        put $text;
    }
}

method !locate-curli-module($module) {
    my $cu = try $*REPO.need(CompUnit::DependencySpecification.new(:short-name($module)));
    unless $cu.DEFINITE {
        note "No such type '$module'";
        exit 1;
    }
    return ~ $cu.repo.prefix.add('sources').add($cu.repo-id);
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
                note "  - '$path" if $!verbose;
                if $path.e {
                    push @paths, $path;
                    next DIR;
                }
            }
        }
    }

    @paths
}
