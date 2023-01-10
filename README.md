# kov-docker-utils

These utils for docker are meant to avoid redoing the same things over and over again.

The first reason ever to create this repo was to make it easy to run tests locally against a dockerized postgresql database that can be initialized with data and spun up with a single command, so the user doesn't need to worry about creating the Dockerfile and docker-compose.yml files, and making sure these files are all working together correctly.
As a result, these tests becomeso much more portable because the dependency to a local postgres database that should be properly configured first to make running the tests possible disappears.

## Installation

Since we are doing most of our development in nodejs anayway, we decided to make this an npm repo, so it can easily be added as a dev dependency.

### Installation as a dev dependency

#### npm > 8
```bash
npm install --save-dev katholiek-onderwijs-vlaanderen/kov-docker-utils
```

#### npm <= 6
```bash
npm install --save-dev git+https://github.com/katholiek-onderwijs-vlaanderen/kov-docker-utils.git
```

### Global installation
```bash
npm install -g katholiek-onderwijs-vlaanderen/kov-docker-utils
```
## Usage

```bash
kov-docker-utils logs 'unique_name'

kov-docker-utils postgres start 'unique_name' 15432 ./dockerintdbfolder
kov-docker-utils postgres exec 'unique_name' 'bash'
kov-docker-utils postgres execsql 'unique_name' 'select * from mytable'
kov-docker-utils postgres stop 'unique_name'
kov-docker-utils postgres cleanup 'unique_name'
kov-docker-utils postgres logs 'unique_name' # needed?
kov-docker-utils postgres isupandrunning 'unique_name'
kov-docker-utils postgres waituntilupandrunning 'unique_name'

kov-docker-utils mssql start 'unique_name' 15432 ./dockerintdbfolder
kov-docker-utils mssql exec 'unique_name' 'bash'
kov-docker-utils mssql execsql 'unique_name' 'select * from mytable'
kov-docker-utils mssql stop 'unique_name'
kov-docker-utils mssql cleanup 'unique_name'
kov-docker-utils mssql logs 'unique_name' # needed?
kov-docker-utils mssql isupandrunning 'unique_name'
kov-docker-utils mssql waituntilupandrunning 'unique_name'

# not implemented
kov-docker-utils elasticsearch start 'project_name'
kov-docker-utils elasticsearch query 'project_name'
kov-docker-utils elasticsearch stop 'project_name'
```

## Change log

2023-01-10: added 'kov-docker-utils mssql' which works very similarly to postgres

## Structure of the repo

* package.json
    bin: 'kov-docker-utils' => npm install -g github.com:kov-docker-utils
* kov-docker-utils
* scripts
  * docker_utils.common.sh
  * kov-docker-utils.postgresdb.sh
  * kov-docker-utils.mssql.sh
