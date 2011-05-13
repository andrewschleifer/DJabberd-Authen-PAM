package DJabberd::Authen::PAM;
use strict;
use base 'DJabberd::Authen';
use Authen::PAM      qw[:constants];
use DJabberd::Log;

our $VERSION = '0.2';
our $logger = DJabberd::Log->get_logger;

sub log {
    $logger;
}

sub set_config_service {
    my ($self, $service) = @_;
    $self->{service} = $service;
}

sub finalize {
    my $self = shift;
    $self->{service} ||= "ssh";
    $logger->info("Authenticating with PAM service ".$self->{service});
}

sub can_retrieve_cleartext { 0 }

sub check_cleartext {
    my ($self, $cb, %args) = @_;
    my $username = $args{username};
    my $password = $args{password};
    my $conn = $args{conn};

    unless ($username =~ /^\w+$/) {
        $cb->reject;
        return;
    }

    my $service = $self->{service};

    # stolen from Authen::Simple::PAM:
    my $handler = sub {
        my @response = ();

        while (@_) {
            my $code    = shift;
            my $message = shift;
            my $answer  = undef;

            if ( $code == PAM_PROMPT_ECHO_ON ) {
                $answer = $username;
            }

            if ( $code == PAM_PROMPT_ECHO_OFF ) {
                $answer = $password;
            }

            push( @response, PAM_SUCCESS, $answer );
        }

        return ( @response, PAM_SUCCESS );
    };


    my $pam = Authen::PAM->new( $service, $username, $handler );

    unless ( ref $pam ) {

        my $error = Authen::PAM->pam_strerror($pam);

        $self->log->error( qq/Failed to authenticate user '$username' using service '$service'. Reason: '$error'/ )
            if $self->log;

        $cb->reject;
        return;
    }

    my $result = $pam->pam_authenticate;

    unless ( $result == PAM_SUCCESS ) {

        my $error = $pam->pam_strerror($result);

        $self->log->debug( qq/Failed to authenticate user '$username' using service '$service'. Reason: '$error'/ )
            if $self->log;

        $cb->reject;
        return;
    }

    $result = $pam->pam_acct_mgmt;

    unless ( $result == PAM_SUCCESS ) {

        my $error = $pam->pam_strerror($result);

        $self->log->debug( qq/Failed to authenticate user '$username' using service '$service'. Reason: '$error'/ )
            if $self->log;

        $cb->reject;
        return 0;
    }

    $self->log->debug( qq/Successfully authenticated user '$username' using service '$service'./ )
        if $self->log;


    $cb->accept;
    return 1;
}

1;

__END__

=head1 NAME

DJabberd::Authen::PAM - authenticate jabber users against a PAM service

=head1 SYNOPSIS

<Vhost yourserver.com>
...
	<Plugin DJabberd::Authen::PAM>
		Service system-auth
	</Plugin>
...
</VHost>

The service defaults to "ssh" if none is specified.

