// Jenkins pipeline to test Terraform modules against multiple versions of Terraform and AWS provider versions. 
// Assumptions:
// - The module is hosted in a Git repository.
// - The module has a version.txt file that contains the current version of the module.
// - The module has a terraform.tf file that contains the required_version and provider versions constraints.
// - The module has examples/ contains an example usage of the module.

properties([
  parameters([
    string(name: 'GIT_REPO_URL', defaultValue: 'git@github.com:itsphoebe/terraform-aws-module-example.git', description: 'Git repository URL to clone. (e.g., git@github.com:itsphoebe/terraform-aws-module-example.git)'),
    string(name: 'GIT_BRANCH', defaultValue: 'main', description: 'Git branch to clone'),
    string(name: 'MODULE_NAME', defaultValue: 'module-example', description: 'Name of the module'),
    string(name: 'TERRAFORM_VERSIONS', defaultValue: '', description: 'Single or comma-separated list of Terraform versions to use (e.g., 1.4.0,1.5.1,1.6.2). Leave blank if using MIN_TERRAFORM_VERSION or MAX_TERRAFORM_VERSION.\nDefault verions are v1.4.0+ and highest minor versions.'),
    string(name: 'MIN_TERRAFORM_VERSION', defaultValue: '', description: 'Minimum Terraform version to use (e.g., 1.4.0). Leave blank if using TERRAFORM_VERSIONS.'),
    string(name: 'MAX_TERRAFORM_VERSION', defaultValue: '', description: 'Maximum Terraform version to use (e.g., 1.6.2). Leave blank if using TERRAFORM_VERSIONS.'),
    booleanParam(name: 'TEST_PROVIDER_VERSIONS', defaultValue: true, description: 'Check to test provider versions'),
    string(name: 'PROVIDER', defaultValue: 'aws', description: 'Provider to test'),
    string(name: 'PROVIDER_VERSION', defaultValue: '', description: 'Single or comma-separated list of provider versions to use (e.g., 5.31.0,5.63.1,5.67.0). Leave blank if using MIN_PROVIDER_VERSION or MAX_PROVIDER_VERSION.\n'),
    string(name: 'MIN_PROVIDER_VERSION', defaultValue: '', description: 'Minimum provider version to use (e.g., 5.82.2). Leave blank if using PROVIDER_VERSION.'),
    string(name: 'MAX_PROVIDER_VERSION', defaultValue: '', description: 'Maximum provider version to use (e.g., 5.88.0). Leave blank if using PROVIDER_VERSION.'),
    booleanParam(name: 'RUN_TERRAFORM_TESTS', defaultValue: true, description: 'Check to run Terraform tests'),
    booleanParam(name: 'DELETE_SNAPSHOT', defaultValue: true, description: 'Delete the SNAPSHOT versions after publishing?')
  ])
])

node {
  // Environment variables
  env.TF_IN_AUTOMATION = 'true'

  // Groovy variables
  def TERRAFORM_VERSIONS = []
  def PROVIDER_VERSIONS = []
  def MODULE_VERSION = ''
  def ARCHIVIST_URL = ''
  def MODULE_VERSION_NAME = ''
  def CSV_REPORT = 'module_versions_results.csv'

  stage('Clean') {
    cleanWs()
  }

  // Pulls Terraform v1.4.0+ and highest minor verions
  stage('Fetch Terraform Versions') {
    script {
      def versions = sh(script: '''
        curl -s https://releases.hashicorp.com/terraform/index.json | jq -r '
          .versions | keys[] | select(test("^[0-9.]+$")) | 
          select((split(".") | map(tonumber)) >= [1,4,0])' |
          sort -V |
          awk -F. '{
            minor = $1"."$2;
            if (minor != prev_minor) {
              if (NR > 1) print max_version;
              max_version = $0;
            }
            max_version = $0;
            prev_minor = minor;
          }
          END { print max_version }'
      ''', returnStdout: true).trim().split('\n')
      TERRAFORM_VERSIONS = versions
      echo "Terraform Versions: ${TERRAFORM_VERSIONS}"
    }
  }

  // Checkout module repository
  stage('Checkout Module Repository') {
    checkout([$class: 'GitSCM', branches: [[name: "*/${params.GIT_BRANCH}"]], userRemoteConfigs: [[credentialsId: 'github', url: params.GIT_REPO_URL]]])
  }

  // Checkout scripts used for this pipeline into subdirectory: scripts/
  stage('Checkout Scripts Repository') {
    checkout([$class: 'GitSCM', branches: [[name: "*/main"]], userRemoteConfigs: [[credentialsId: 'github', url: "git@github.com:itsphoebe/module-version-tester.git"]], extensions: [[$class: 'RelativeTargetDirectory', relativeTargetDir: 'scripts']]])
  }

  // Pulls provider versions 

  // ALTERNATIVE METHOD: PULL PROVIDER VERSIONS VIA GIT TAGS 
  // Currently only supports AWS provider
  // if (params.TEST_PROVIDER_VERSIONS) {
  //   stage('Pull Providers Release Tags') {
  //     script {
  //       def releases = sh(script: '''
  //         ./scripts/get_releases.sh
  //       ''', returnStdout: true).trim().split('\n')
  //       PROVIDER_VERSIONS = releases
  //       echo "Provider Versions: ${PROVIDER_VERSIONS}"
  //     }
  //   }
  // }
  if (params.TEST_PROVIDER_VERSIONS) {
    stage('Pull Providers Release Tags') {
      script {
        def versions = sh(script: '''
          curl -s https://releases.hashicorp.com/terraform-provider-${PROVIDER}/index.json | jq -r '
            .versions | keys[] | select(test("^[0-9.]+$"))' |
            sort -V |
            awk -F. '{
              minor = $1"."$2;
              if (minor != prev_minor) {
                if (NR > 1) print max_version;
                max_version = $0;
              }
              max_version = $0;
              prev_minor = minor;
            }
            END { print max_version }'
        ''', returnStdout: true).trim().split('\n')
        PROVIDER_VERSIONS = versions
        echo "Provider Versions: ${PROVIDER_VERSIONS}"
      }
    }
  }


  // Comparator function to compare version strings
  def compareVersions = { v1, v2 ->
    def parts1 = v1.tokenize('.').collect { it.toInteger() }
    def parts2 = v2.tokenize('.').collect { it.toInteger() }
    for (int i = 0; i < Math.max(parts1.size(), parts2.size()); i++) {
      def part1 = i < parts1.size() ? parts1[i] : 0
      def part2 = i < parts2.size() ? parts2[i] : 0
      if (part1 != part2) {
        return part1 <=> part2
      }
    }
    return 0
  }

  // Filter versions based on min and max version
  def filterVersions = { versions, minVersion, maxVersion ->
    def filteredVersions = versions
    if (minVersion) {
      filteredVersions = filteredVersions.findAll { compareVersions(it, minVersion) >= 0 }
    }
    if (maxVersion) {
      filteredVersions = filteredVersions.findAll { compareVersions(it, maxVersion) <= 0 }
    }
    return filteredVersions
  }

  // Process versions based on input parameters
  // If paramVersions is provided, use it. Otherwise, use min/max version filtering.
  def processVersions = { paramVersions, minVersion, maxVersion, defaultVersions ->
    if (paramVersions) {
      def filteredVersions = paramVersions.split(',').collect { it.trim() }
      return filteredVersions.unique()
    } else if (minVersion || maxVersion) {
      return filterVersions(defaultVersions, minVersion?.trim(), maxVersion?.trim())
    }
    return defaultVersions
  }

  // Process versions based on input parameters
  TERRAFORM_VERSIONS = processVersions(params.TERRAFORM_VERSIONS, params.MIN_TERRAFORM_VERSION, params.MAX_TERRAFORM_VERSION, TERRAFORM_VERSIONS)
  if (params.TEST_PROVIDER_VERSIONS) {
    PROVIDER_VERSIONS = processVersions(params.PROVIDER_VERSION, params.MIN_PROVIDER_VERSION, params.MAX_PROVIDER_VERSION, PROVIDER_VERSIONS)
  }

  // Validate filtered versions are not empty before continuing
  stage('Validate Versions') {
    if (TERRAFORM_VERSIONS.size() == 0 || (params.TEST_PROVIDER_VERSIONS && PROVIDER_VERSIONS.size() == 0)) {
      error("Provided TERRAFORM_VERSIONS or PROVIDER_VERSIONS could not be validated. Please ensure correct syntax. Stopping the pipeline.")
    }
      // Echo the final versions
    echo "Final TERRAFORM_VERSIONS: ${TERRAFORM_VERSIONS}"
    echo "Final PROVIDER_VERSIONS: ${PROVIDER_VERSIONS}"

    // Create headers for CSV report
    sh """echo "Type,Version,Status,Deprecation/Error,Create,Destroy,Update" >> ${CSV_REPORT}"""
  }

  try {
    stage('Prep Testing') {
      // Assumes required_version is in terraform.tf
      // Update the required_version of module to allow a min of Terraform v1.4.0
      sh """
        echo 'Set required_version to accept minimum version of Terraform v1.4 to allow testing'
        sed -i '' 's/required_version = ".*"/required_version = ">= 1.4.0"/' terraform.tf
      """
      // Assumes module_version is in version.txt
      // Used to set configurations back to applied module version when destroying
      try {
        MODULE_VERSION = readFile('version.txt').trim()
        echo "Version from version.txt: ${MODULE_VERSION}"
      } catch (Exception e) {
        error "Failed to read 'version.txt'"
      }
    }

    // Terraform validation
    stage('Terraform Init & Validate') {
      TERRAFORM_VERSIONS.each { version ->
        stage(version) {
          // Terraform validation via 'terraform validate' command
          catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE', message: "Failed to validate Terraform configuration for version ${version}") {
            try {
              sh """
                tfswitch ${version}
                terraform --version
                terraform init -no-color
                terraform validate -no-color
                echo "TERRAFORM,${version},SUCCESS" >> ${CSV_REPORT}
              """
            } catch (Exception e) {
              echo "Error occurred: ${e.getMessage()}"
              sh """
                echo "TERRAFORM,${version},FAILURE" >> ${CSV_REPORT}
              """
              error()
            }
          }
        }
      }
    }

  // Provider validation
  if (params.TEST_PROVIDER_VERSIONS) {
    stage('Apply current Terraform module for provider version testing') {
      echo 'Apply module...'

      // Assumes examples directory contains an example usage of module
      withCredentials([string(credentialsId: 'TFE-migrate-from-admin-token', variable: 'TFE_API_TOKEN')]) {
        script {
          // Create terraform.tf file containing details to map to an emphemeral workspace to deploy the module
          sh'''
            cd examples
            cat <<EOF > terraform.tf
terraform {
  cloud {
    hostname = "tfe-migrate-from.phoebe-lee.sbx.hashidemos.io"
    organization = "phoebe-test"

    workspaces {
      name = "module-version-tester"
    }
  }
}
EOF
          '''
        }
      }
      // Apply module as described in examples directory
      // Failure of init or apply will fail pipeline
      sh """
        cd examples
        terraform init -no-color || exit 1
        terraform apply -no-color -auto-approve || exit 1
      """
    }

    // Ensure module is published in TFE registry
    stage('Publish module') {
      echo 'Publishing to TFE Registry...'
      withCredentials([string(credentialsId: 'TFE-migrate-from-admin-token', variable: 'TFE_API_TOKEN')]) {
        script {
          def response = sh(
            script: '''
              curl -sS --write-out "%{http_code}" --request POST \
                --url https://tfe-migrate-from.phoebe-lee.sbx.hashidemos.io/api/v2/organizations/phoebe-test/registry-modules/ \
                --header "Authorization: Bearer $TFE_API_TOKEN" \
                --header "Content-Type: application/vnd.api+json" \
                --data '{
                  "data": {
                    "type": "registry-modules",
                    "attributes": {
                      "name": "'${MODULE_NAME}'",
                      "provider": "'${PROVIDER}'",
                      "registry-name": "private",
                      "no-code": false
                    }
                  }
                }'
            ''',
            returnStdout: true
          ).trim()
          def httpCode = response.substring(response.length() - 3)

          echo "Response Code: ${httpCode}"
          // if 200 or 422, continue, otherwise fail
          if (httpCode != '200' && httpCode != '422') {
            error "Failed to publish module. HTTP Response Code: ${httpCode}"
          }
        }
      }
    }

    // For each provider version, create a SNAPSHOT version with updated provider version
    // Assumes provider version is in terraform.tf  
    PROVIDER_VERSIONS.each { version ->
      MODULE_VERSION_NAME = "${MODULE_VERSION}-SNAPSHOT-${PROVIDER}-${version}"
      stage(version) {
        sh"""
          sed -i '' '/${PROVIDER} = {/,/}/s/version = "[^"]*"/version = "${version}"/' terraform.tf
        """

        // Create module version in TFE registry
        // Get the archivist URL to upload the module
        stage('Create SNAPSHOT version') {
          echo "Creating ${MODULE_VERSION_NAME} version..."
          withCredentials([string(credentialsId: 'TFE-migrate-from-admin-token', variable: 'TFE_API_TOKEN')]) {
            script {
              def response = sh(
                script:'''
                  curl -sS --write-out "%{http_code}" --request POST \
                    --url https://tfe-migrate-from.phoebe-lee.sbx.hashidemos.io/api/v2/organizations/phoebe-test/registry-modules/private/phoebe-test/${MODULE_NAME}/${PROVIDER}/versions \
                    --header "Authorization: Bearer $TFE_API_TOKEN" \
                    --header "Content-Type: application/vnd.api+json" \
                    --data '{
                    "data": {
                      "attributes": {
                        "version": "''' + MODULE_VERSION_NAME + '''"
                      },
                      "type":"registry-modules"
                    }
                  }'
                ''',
                returnStdout: true
              ).trim()
              def httpCode = response.substring(response.length() - 3)
              if (httpCode != '201') {
                error "Failed to create SNAPSHOT version. HTTP Response Code: ${httpCode}"
              }
              response = response.substring(0, response.length() - 3) // remove http code from response
              echo "Response: ${response}"

              // Extract archivist URL from response
              ARCHIVIST_URL = sh(
                script: "jq -r '.data.links.upload' <<< '${response}'",
                returnStdout: true
              ).trim()
            }
          }
        }

        // Publish updated module to the TFE registry
        stage('Publish SNAPSHOT version') {
          // Create tarball and upload
          sh"""
            tar zcvf module.tar.gz --exclude='.terraform' --exclude='module.tar.gz' --exclude='terraform_plan_output.log' --exclude=${CSV_REPORT} --exclude='scripts*' * 
            curl -s -T module.tar.gz ${ARCHIVIST_URL}

            echo "sleep may be needed to allow upload to complete (status: reg_ingressing)"
            sleep 5
          """

          // Check if the module version is published
          withCredentials([string(credentialsId: 'TFE-migrate-from-admin-token', variable: 'TFE_API_TOKEN')]) {
            script {
              def response = sh(
                script:'''
                  curl -sS --write-out "%{http_code}" --request GET \
                    --url https://tfe-migrate-from.phoebe-lee.sbx.hashidemos.io/api/v2/organizations/phoebe-test/registry-modules/private/phoebe-test/${MODULE_NAME}/${PROVIDER}/ \
                    --header "Authorization: Bearer $TFE_API_TOKEN" \
                    --header "Content-Type: application/vnd.api+json" \
                ''',
                returnStdout: true
              ).trim()
              def httpCode = response.substring(response.length() - 3)
              if (httpCode != '200') {
                error "Failed to publish SNAPSHOT version. HTTP Response Code: ${httpCode}"
              }
              response = response.substring(0, response.length() - 3)
              def status = sh(
                script: "jq -r '.data.attributes[\"version-statuses\"][] | select(.version == \"${MODULE_VERSION_NAME}\") | .status' <<< '${response}'",
                returnStdout: true
              ).trim()
              echo "Version status: ${status}"  
            }
          }
        }

        // Check changes against new SNAPSHOT version
        stage('Validate Provider Version') {
          echo "Validating ${PROVIDER} provider version ${version}..."
          // Fails stage if init or plan fails, Build result is UNSTABLE
          // If plan output contains Warnings, Errors, or planned actions, error to trigger plan_extractor.py script to extract output
          catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE', message: "Failed to validate ${PROVIDER} provider configuration for version ${version}") {
            try {
              // Plan must be performed to see changes of provider versions
              sh """
                cd examples
                # assumes main.tf in examples/
                sed -i '' '/module /,/}/s/version = "[^"]*"/version = "${MODULE_VERSION_NAME}"/' main.tf
                terraform init -upgrade -no-color
                terraform plan -detailed-exitcode -no-color 2>&1 | tee terraform_plan_output.log
                if grep -E -q "Warning:|Error:|Terraform will perform the following actions:" terraform_plan_output.log; then
                  echo "Warnings, Errors, or planned actions found in terraform plan."
                  exit 1
                fi
                echo "${PROVIDER},${version},SUCCESS" >> ../${CSV_REPORT}
              """
            } catch (Exception e) {
              // Run script to extract plan output to CSV
              sh "python3 scripts/plan_extractor.py examples/terraform_plan_output.log ${CSV_REPORT} ${PROVIDER} ${version}"
              error("Extracted plan output to CSV.")
            }
          }
        }
      }
    }
  }
    // Optional stage to run Terraform tests. Terraform tests should be in tests/ directory if using this stage.
    // Uses junit Jenkins plugin to publish test results.
    if (params.RUN_TERRAFORM_TESTS) {
      // Tests currently running on v1.11.3 (Minimum version v1.6. Mocking must use minimum version v1.7)
      stage('Run Terraform Tests') {
        def version = '1.11.3'
        sh """
          if [ ! -d "tests/" ]; then
            echo "Directory 'tests/' does not exist. Failing the stage."
            exit 1
          fi
          tfswitch ${version}
          terraform init -upgrade -no-color
          terraform test -no-color -junit-xml=tests-results.xml 
        """
        junit 'tests-results.xml'
      }
    }

  } finally {
    // Archive the CSV report
    stage('Archive Results') {
      archiveArtifacts artifacts: CSV_REPORT, allowEmptyArchive: true
    }

    // If providers were tested:
    if (params.TEST_PROVIDER_VERSIONS) {
      // Delete module SNAPSHOT versions pubished to registry for testing
        stage('Delete SNAPSHOT module versions') { 
        PROVIDER_VERSIONS.each { version ->

          MODULE_VERSION_NAME = "${MODULE_VERSION}-SNAPSHOT-${PROVIDER}-${version}"

          // optional stage to delete SNAPSHOT version
          if (params.DELETE_SNAPSHOT) {
            stage('Delete SNAPSHOT version') {
              withCredentials([string(credentialsId: 'TFE-migrate-from-admin-token', variable: 'TFE_API_TOKEN')]) {
                script {
                  def response = sh(
                    script:'''
                      curl -sS --write-out "%{http_code}" --request DELETE \
                        --url https://tfe-migrate-from.phoebe-lee.sbx.hashidemos.io/api/v2/organizations/phoebe-test/registry-modules/private/phoebe-test/${MODULE_NAME}/${PROVIDER}/''' + MODULE_VERSION_NAME + ''' \
                        --header "Authorization: Bearer $TFE_API_TOKEN"
                    ''',
                    returnStdout: true
                  ).trim()
                  echo "Response: ${response}"
                }
              }
            }
          } else {
            echo "SNAPSHOT version ${MODULE_VERSION_NAME} was not be deleted."
          }
                
        }
      }
      // Destroy the module deployed to test Provider versions
      stage('Destroy') {
        // Revert back to original module version for destroy
        sh"""
          cd examples
          # assumes main.tf in examples/
          sed -i '' '/module /,/}/s/version = "[^"]*"/version = "${MODULE_VERSION}"/' main.tf
          echo "Destroying Terraform resources..."
          terraform init -upgrade -no-color
          terraform destroy -auto-approve -no-color
        """
      }
    }

    stage('Clean') {
      cleanWs()
    }
  }
}