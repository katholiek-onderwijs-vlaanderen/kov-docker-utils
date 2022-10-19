# docker-utils

These utils are meant to avoid redoing the same things over and over again.

The first reason ever to create this repo was to make it easy to run tests locally against a dockerized postgresql database that can be initialized with data and spun up with a single command, so the user doesn't need to worry about creating the Dockerfile and docker-compose.yml files, and making sure these files are all working together correctly.
As a result, these tests becomeso much more portable because the dependency to a local postgres database that should be properly configured first to make running the tests possible disappears.

## Installation

Since we are doing most of our development in nodejs anayway, we decidedto make this an npm repo, so it can easily be added as a dev dependency.

### Installation as a dev depencdency
```bash
npm install --save-dev git@github.com:katholiek-onderwijs-vlaanderen/docker-utils.git
```
### Global installation
```bash
npm install -g git@github.com:katholiek-onderwijs-vlaanderen/docker-utils.git
```
## Usage

```bash
docker-utils logs 'unique_name'

docker-utils postgres start 'unique_name' 15432 ./dockerintdbfolder
docker-utils postgres execsql 'unique_name'
docker-utils postgres stop 'unique_name'
docker-utils postgres cleanup 'unique_name'
docker-utils postgres logs 'unique_name' # needed?
docker-utils postgres isupandrunning 'unique_name'
docker-utils postgres waituntilupandrunning 'unique_name'


docker-utils elasticsearch start 'project_name'
docker-utils elasticsearch query 'project_name'
docker-utils elasticsearch stop 'project_name'
```

* package.json
    bin: 'docker-utils.sh' => npm install -g github.com:docker-utils
* docker-utils
* scripts
  * docker_utils.common.sh
  * docker-utils.postgresdb.sh
  * docker-utils.elasticsearch.sh


### postgresqlserver

#### runpostgresqldb

* create dockerfile that installs the DB on a docker
* create docker-compose file to run the db
* run docker compose file and wait until db up and running
* assumptions: folder to init DB willbe copied to /docker-entrypoint-initdb.d so it will run when the container first starts.

```bash
runpostgresqldb 'project_name' 'folder to init database (bv ./test/sql)' <postgres version> <local_portnum>
```

#### executesqlonpostgresqldb
```bash
runpostgresqldb 'project_name' 'select * from mytable'
```

docker execute -it psql ... 'sql' => 
runpostgresqldb && execute "copy postgres.backdb to postgres" && runtestsonpostgresdb && stopcontainer

#### stoppostgresqldb
```bash
stoppostgresqldb 'project_name'
```
#### stoppostgresqldb
```bash
cleanuppostgresqldb 'project_name'
```
