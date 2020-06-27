unit class Rakudoc:ver<0.2.0>;

use Pod::To::Text;
# Use our local version until development settles down
use Pod::Cache;

has $.cache;
has @!doc-source;
has @!extensions = <pod6 rakudoc pod p6 pm pm6>;
has $!verbose;

method !path-for-fragment($fragment is copy, :@extensions!) {
    note "looking for $fragment";
    # Note: IO::Spec::Win32.splitdir splits on both '/' and '\', so
    # $fragment can be a Unixy or OS-specific path
    my @parts = $*SPEC.splitdir($fragment);
    $fragment = $*SPEC.catdir(@parts).IO;

    my $matrix = (@!doc-source X ($fragment.extension ?? '' !! @extensions));

    for @$matrix -> ($dir, $ext) {
        my $path = $dir.add($fragment).extension(:0parts, $ext);
        note "  - $path";
        return ~$path if $path.e;
    }

    Nil;
}

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
    if self!path-for-fragment($fragment, :@extensions) -> $path {
        $!cache.pod: $path;
    }
    else {
        die "NYI parse '$fragment' & locate module";
    }
}

method show-it($pod) {
    my $text = pod2text($pod);
    my $pager = $*OUT.t && [//] |%*ENV<RAKUDOC_PAGER PAGER>, 'more';
    if $pager {
        $pager = run :in, $pager;
        $pager.in.spurt($text, :close);
    }
    else {
        put $text;
    }
}

sub locate-curli-module($module) {
    my $cu = try $*REPO.need(CompUnit::DependencySpecification.new(:short-name($module)));
    unless $cu.DEFINITE {
        note "No such type '$module'";
        exit 1;
    }
    return ~ $cu.repo.prefix.child('sources/' ~ $cu.repo-id);
}
