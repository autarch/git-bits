package GitBits::Mirror;

use Moose;
use namespace::autoclean;
use autodie qw( :all );

use Git::Wrapper;
use Net::GitHub;
use Sys::Hostname qw( hostname );

has owner => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_owner',
);

has login => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_login',
);

has token => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_token',
);

has repo => (
    is       => 'ro',
    isa      => 'Str',
    required => 1,
);

has hostname => (
    is      => 'ro',
    isa     => 'Str',
    lazy    => 1,
    builder => '_build_hostname',
);

has _github => (
    is       => 'ro',
    isa      => 'Git::Wrapper',
    init_arg => undef,
    lazy     => 1,
    default  => sub {
        Net::GitHub->new(
            owner => $self->owner(),
            token => $self->token(),
        );
    },
);

has _git => (
    is       => 'ro',
    isa      => 'Git::Wrapper',
    init_arg => undef,
    lazy     => 1,
    default  => sub { Git::Wrapper->new() },
);

sub run {
    my $self = shift;

    $self->_maybe_create_repo();
    $self->_push_all();
}

sub _maybe_create_repo {
    my $self = shift;

    my $repo = $self->_github()->repos()->search( $self->repo() );

    return if $repo && @{$repo} && defined $repo->[0]{name};

    $self->_out(
        'Creating new ' . $self->repo() . " repository on github\n" );

    $self->_github()->repos()->create(
        $self->repo(),
        'Mirror of ' . $self->repo() . ' on ' . $self->_hostname(),
        undef,
        1,
    );

    return;
}

sub _push_all {
    my $self = shift;

    $self->_maybe_add_github_remote();

    $self->_out('Pushing all branches to github');

    $self->_git()->push( '--mirror', 'github' );

    return;
}

sub _maybe_add_github_remote {
    my $self = shift;

    my %remotes = map { chomp; $_ => 1 } split /\n/,
        $self->_git()->remote('show');
    return if $remotes{github};

    $self->_out('Adding github as new remote');

    $self->_git()
        ->remote( 'add', 'github',
        'https://github.com/' . $self->owner() . '/' . $self->repo() );

    return;
}

sub _build_owner {
    my $self = shift;

    return $self->_git_config('github.owner');
}

sub _build_token {
    my $self = shift;

    return $self->_git_config('github.token');
}

sub _build_hostname {
    my $self = shift;

    return hostname();
}

sub _git_config {
    my $self = shift;
    my $name = shift;

    my $value = `git config --global $name`;

    die "Could not find a $name key in the global git config"
        unless defined $value;

    chomp $value;

    return $value;
}

sub _out {
    my $self = shift;

    print @_;
}

__PACKAGE__->meta()->make_immutable();
