unit class Pod::Cache;

has %.sources is SetHash;

has IO::Path $!cache-path;
has $!precomp-repo;
has %!errors;
has %!ids;


submethod BUILD(
    :$cache-path = 'rakudoc_cache',
)
{
    $!cache-path = $cache-path.IO.resolve(:completely);
    $!precomp-repo = CompUnit::PrecompilationRepository::Default.new(
        :store(CompUnit::PrecompilationStore::File.new(:prefix($!cache-path))),
    );
}

method !compunit-handle($pod-file-path) {
    my $t = $pod-file-path.IO.modified;
    my $id = CompUnit::PrecompilationId.new-from-string($pod-file-path);
    %!ids{$pod-file-path} = $id;
    my ($handle, $) = $!precomp-repo.load( $id, :src($pod-file-path), :since($t) );
    unless $handle {
        note "Caching '$pod-file-path' to '$!cache-path'";
        $handle = $!precomp-repo.try-load(
            CompUnit::PrecompilationDependency::File.new(
                :src($pod-file-path),
                :$id,
                :spec(CompUnit::DependencySpecification.new(:short-name($pod-file-path))),
            )
        );
        note "    - Survived with handle {$handle // 'NULL'}";
    }

    ++%!sources{$pod-file-path};
    return $handle;
}

#| pod(Str $pod-file-path) returns the pod tree in the pod file
multi method pod(CompUnit::Handle $handle) {
    use nqp;
    nqp::atkey($handle.unit, '$=pod')
}

multi method pod(Str $pod-file-path is copy) {
    # Canonical form for lookup consistency
    $pod-file-path = ~$pod-file-path.IO.resolve(:completely);

    my $handle;
    if %!ids{$pod-file-path}:exists {
        $handle = $!precomp-repo.try-load(
            CompUnit::PrecompilationDependency::File.new(
                :src($pod-file-path),
                :id(%!ids{$pod-file-path})
                ),
            );
    }
    else {
        $handle = self!compunit-handle($pod-file-path);
    }

    self.pod($handle);
}
