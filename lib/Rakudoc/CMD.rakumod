unit module Rakudoc::CMD;

use Rakudoc;

our proto sub MAIN(|) is export(:MAIN) {
    {*}
}

# $*USAGE shows the type name as "[-d|--doc=<Directory> ...]", so the
# singular "Directory" reads better, even though it is an array
subset Directory of Positional where { all($_) ~~ Str };

multi sub MAIN(
    Str:D $query,
    Bool :v(:$verbose),
    #| Directories to search for documentation
    Directory :d(:$doc) = Empty,
    #| Only use directories specified with --doc / $RAKUDOC
    Bool :D(:$no-default-docs),
)
{
    my $rkd = Rakudoc.new:
        :doc-source($doc),
        :$no-default-docs,
        :$verbose,
        ;

    my @docs = |$rkd.search-doc-dirs($query), |$rkd.search-compunits($query);
    $rkd.display(@docs);
}

multi sub MAIN(
    Bool :h(:$help)!
)
{
    &*USAGE(:okay);
}
