unit module Rakudoc::CMD;

use Rakudoc;

our proto sub MAIN(|) is export(:MAIN) {
    {*}
}

# $*USAGE shows the type name as, e.g., "[-d|--doc=<Directory> ...]", so the
# singular ("Directory") reads better, even though it is an array
subset Directory of Positional where { all($_) ~~ Str };

multi sub MAIN(
    #| Example: 'IO::Path' 'IO::Path.dir' '.dir'
    *@query ($, *@),

    #| Directories to search for documentation
    Directory :d(:$doc) = Empty,
    #| Only use directories specified with --doc / $RAKUDOC
    Bool :D(:$no-default-docs),

    Bool :v(:$verbose),
) {
    my $rkd = Rakudoc.new:
        :doc-source($doc),
        :$no-default-docs,
        :$verbose,
        ;

    my @requests = @query.map: { $rkd.request: $_ };
    my @docs = @requests.map: { | .search };
    $rkd.display(|@docs);
}

multi sub MAIN(Bool :h(:$help)!, |) {
    &*USAGE(:okay);
}
