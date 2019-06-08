package App::CartoCSS2Tegola;

# ABSTRACT: Convert CartoCSS project file to tegola configuration

use 5.010001;
use strict;
use warnings;
use Carp;

use Moose;
with 'MooseX::Getopt';

use YAML::XS;
use TOML::Dumper;
use DBI;


=head1 SYNOPSIS

	use App::CartoCSS2Tegola;

	App::CartoCSS2Tegola->new_with_options()->run() unless caller();

=head1 DESCRIPTION

App::CartoCSS2Tegola is intended to convert a CartoCSS project file to a
configuration file for Tegola. It configures a map called C<osm> that contains
all PostGIS layers from the CartoCSS configuration, under the same name, using
the same SQL query and thus data.

=head1 USAGE

In order to create the configuration file and to actually render the vector
tiles with Tegola, you'll need an C<osm2pgsql>-based rendering database that was
setup the same way as it would be required for the CartoCSS style that should be
converted, i.e. for the OpenStreetMap Carto style, you'll have to follow the
instructions in their
L<INSTALL.md|https://github.com/gravitystorm/openstreetmap-carto/blob/master/INSTALL.md>
documentation. The configuration can then be created as follows:

	cartocss2tegola \
		--db-user gis \
		--db-password gis \
		--db-name gis \
		--mml ../openstreetmap-carto/project.mml > openstreetmap-carto.toml

You might want to pass other parameters as well, see C<cartocss2tegola --help>
for information about the available parameters.

Once the configuration has been built, C<tegola> can be started:

	tegola serve --config=path/to/tegola.config

By default, it will listen on port 8080. The capabilities can be requested at
L<http://localhost:8080/capabilities/osm.json>, this JSON data will also contain
URLs of the different layers if needed and the URL of the vector tiles that
contain all layers. The vector tiles can now be rendered with Mapbox GL, Tangram,
OpenLayers, etc. using a style which supports the layers and data in the
generated vector tiles.

=head1 METHODS

=cut


has 'mml' => (
	is            => 'ro',
	isa           => 'Str',
	required      => 1,
	documentation => 'Path to CartoCSS project.mml file.',
);

has 'max_zoom' => (
	traits        => ['Getopt'],
	cmd_flag      => 'max-zoom',
	is            => 'ro',
	isa           => 'Int',
	documentation => 'Maximum zoom level for map layers. Overrides the values from the CartoCSS project file.',
);

has 'port' => (
	is            => 'ro',
	isa           => 'Int',
	default       => 8080,
	documentation => 'Port where Tegola should run.',
);

has 'cache' => (
	traits        => ['Getopt'],
	cmd_flag      => 'cache',
	is            => 'ro',
	isa           => 'Str',
	default       => 'file',
	documentation => 'Type of cache to use. Defaults to "file"',
);

has 'cache_dir' => (
	traits        => ['Getopt'],
	cmd_flag      => 'cache',
	is            => 'ro',
	isa           => 'Str',
	default       => '/tmp/tegola-cache',
	documentation => 'Cache directory for file cache.',
);

has 'db_host' => (
	traits        => ['Getopt'],
	cmd_flag      => 'db-host',
	is            => 'ro',
	isa           => 'Str',
	default       => 'localhost',
	documentation => 'Database host to connect to.',
);

has 'db_port' => (
	traits        => ['Getopt'],
	cmd_flag      => 'db-port',
	is            => 'ro',
	isa           => 'Str',
	default       => 5432,
	documentation => 'Database port to connect to.',
);

has 'db_user' => (
	traits        => ['Getopt'],
	cmd_flag      => 'db-user',
	is            => 'ro',
	isa           => 'Str',
	required      => 1,
	documentation => 'Database user.',
);

has 'db_password' => (
	traits        => ['Getopt'],
	cmd_flag      => 'db-password',
	is            => 'ro',
	isa           => 'Str',
	required      => 1,
	documentation => 'Database password.',
);

has 'db_name' => (
	traits        => ['Getopt'],
	cmd_flag      => 'db-name',
	is            => 'ro',
	isa           => 'Str',
	required      => 1,
	documentation => 'Database name.',
);

has 'db_max_connections' => (
	traits        => ['Getopt'],
	cmd_flag      => 'db-max-connections',
	is            => 'ro',
	isa           => 'Int',
	default       => 100,
	documentation => 'Maximum number of database connections to establish.',
);

has 'dbi_str' => (
	traits        => ['Getopt'],
	cmd_flag      => 'dbi-str',
	is            => 'ro',
	isa           => 'Str',
	documentation => 'DBI connection string to determine columns, will be built fromm connection parameters if not given.',
);

has 'dbh' => (
	traits  => ['NoGetopt'],
	is      => 'ro',
	isa     => 'DBI::db',
	lazy    => 1,
	default => sub {
		my ($self) = @_;
		my @connect_param = $self->dbi_str()
			? ($self->dbi_str())
			: (
				'dbi:Pg:dbname=' . $self->db_name()
					. ';host=' . $self->db_host()
					. ';port=' . $self->db_port()
					. ';',
				$self->db_user(),
				$self->db_password()
			)
		;
		my $dbh = DBI->connect(@connect_param);
		$dbh->{pg_placeholder_dollaronly} = 1;  # ? is operator for hstore
		return $dbh;
	},
);


my %geometry_type_mapping = (
	linestring => 'LineString',
	point      => 'Point',
	polygon    => 'Polygon',
);


=head2 run

Run the application.

=head3 Result

The Tegola configuration on STDOUT.

=cut

sub run {
	my ($self) = @_;

	my $mml_data = YAML::XS::LoadFile($self->mml());
	my @carto_layers = @{$mml_data->{Layer}};
	my @postgis_layers = grep {
		defined $_->{Datasource}->{'<<'}->{type}
			&& $_->{Datasource}->{'<<'}->{type} eq 'postgis'
	} @carto_layers;
	my @layers;
	my @map_layers;

	for my $layer (@postgis_layers) {
		my $sql = $layer->{Datasource}->{table};
		$sql =~ s{\\d}{\\\\d}gx;
		$sql =~ s{\\(\d+)}{\\\\$1}gx;
		$sql =~ s{\\\.}{\\\\.}gx;
		my @columns = map {
			'"' . $_ . '"'
		} grep {
			$_ ne 'way'
		} $self->get_columns($sql);
		unshift @columns, 'ST_AsBinary(way) AS geom';
		my $columns = join(', ',  @columns);

		push @layers, {
			name               => $layer->{id},
			geometry_fieldname => 'geom',
			defined $layer->{geometry}
				? (geometry_type => $geometry_type_mapping{$layer->{geometry}})
				: (),
			sql                => 'SELECT ' . $columns . ' FROM ' . $sql . ' WHERE way && !BBOX!',
		};
		my $min_zoom = $layer->{properties}->{minzoom}
			? defined $self->max_zoom() && $self->max_zoom() < $layer->{properties}->{minzoom}
				? $self->max_zoom()
				: $layer->{properties}->{minzoom}
			: $layer->{properties}->{minzoom};
		my $max_zoom = $layer->{properties}->{maxzoom}
			? defined $self->max_zoom() && $self->max_zoom() < $layer->{properties}->{maxzoom}
				? $self->max_zoom()
				: $layer->{properties}->{maxzoom}
			: $self->max_zoom();
		push @map_layers, {
			provider_layer => 'osm.' . $layer->{id},
			defined $min_zoom
				? (min_zoom => $min_zoom)
				: (),
			defined $max_zoom
				? (max_zoom => $max_zoom)
				: (),
		};
	}

	my $config = {
		webserver => {
			port => ':' . $self->port(),
		},
		providers => [{
			name            => 'osm',
			type            => 'postgis',
			host            => $self->db_host(),
			port            => $self->db_port(),
			database        => $self->db_name(),
			user            => $self->db_user(),
			password        => $self->db_password(),
			max_connections => $self->db_max_connections(),
			srid            => 3857,
			layers          => \@layers,
		}],
		maps => [{
			name   => 'osm',
			layers => \@map_layers,
		}],
	};

	if ($self->cache() ne 'none') {
		$config->{cache} = {
			type     => $self->cache(),
			basepath => $self->cache_dir(),
		}
	}

	my $config_str = TOML::Dumper->new->dump($config);
	$config_str =~ s{\\/}{/}gx;
	say $config_str;

	return;
}


=head2 get_columns

Get result columns from a given CartoCSS SQL statement.

=head3 Parameters

This method expects positional parameters.

=over

=item sql

The SQL statement string.

=back

=head3 Result

A list with the result columns.

=cut

sub get_columns {
	my ($self, $sql) = @_;

	$sql =~ s{!scale_denominator!}{1}gix;
	$sql =~ s{!bbox!}{ST_MakeEnvelope(-180.0, -85.06, 180.0, 85.06, 4326)}gix;
	$sql =~ s{!pixel_(?:width|height)!}{42}gix;
	$sql = 'SELECT * FROM ' . $sql . ' LIMIT 0';
	my $sth = $self->dbh()->prepare($sql);
	my $rv = $sth->execute();
	unless ($rv) {
		croak("Failed to execute $sql");
	}

	return @{$sth->{NAME}};
}


=head1 SEE ALSO

=over

=item *

L<https://tegola.io/> - Tegola, an open source vector tile server written in Go.

=item *

L<https://github.com/mapbox/carto> - CartoCSS, fast CSS-like map stylesheets.

=item *

L<https://github.com/gravitystorm/openstreetmap-carto> - OpenStreetMap Carto, a
general-purpose OpenStreetMap mapnik style, in CartoCSS.

=back

=cut


__PACKAGE__->meta()->make_immutable();

1;
