unit class Rakudoc:ver<0.2.0>;

use Pod::To::Text;
# Use our local version until development settles down
use Pod::From::Cache;

has $.cache;
has $!verbose;

submethod TWEAK(:@doc-source is copy, :$!verbose) {
    if !@doc-source and %*ENV<RAKUDOC> {
        @doc-source = %*ENV<RAKUDOC>.split(',').map(*.trim);
    }
    $!cache = Pod::From::Cache.new:
        :lazy,
        :@doc-source,
        #:cache-path('./tmp/.cache-doc'),
        ;
}

method get-it($fragment) {
    $!cache.pod: $fragment;
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
