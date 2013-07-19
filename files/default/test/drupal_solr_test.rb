require 'minitest/spec'
# minitest recipe
# Cookbook Name:: deploy-drupal
# Spec:: drupal_solr
#
include MiniTest::Chef::Assertions
include MiniTest::Chef::Context
include MiniTest::Chef::Resources

# Custom Tests:
class TestSolr < MiniTest::Chef::TestCase
  def test_tomcat
    tomcat_root_url = "http://localhost:#{node['tomcat']['port']}"
    command = "curl -I #{tomcat_root_url} | grep -q Apache-Coyote"
    txt = "curled #{tomcat_root_url} and expected an HTTP response from a Tomcat server"
    
    Chef::Log.info "curling #{tomcat_root_url}"
    assert_sh command , txt
  end
  def test_solr_server
    solr_ping_request = "http://localhost:#{node['tomcat']['port']}/" +
                        node['deploy-drupal']['solr']['app_name'] +
                        "/admin/ping"
    command = "curl -I #{solr_ping_request} | grep OK"
    txt = "requested solr server at #{solr_ping_request} with a wildcard query"
    
    Chef::Log.info "curling #{solr_ping_request}"
    assert_sh command , txt
  end
  def test_drupal_solr_module
    drupal_root  = node['deploy-drupal']['deploy_dir']  + "/" +
                        node['deploy-drupal']['project_name'] + "/" +
                        node['deploy-drupal']['drupal_root_dir']
    command = "drush --root=#{drupal_root} vget search_active_modules | grep apachesolr"
    txt = "expected to find apachesolr in active Drupal search modules"
    assert_sh command , txt
  end
  def test_drupal_solr_indexing 
    # number of automatically generated nodes for testing
    n = 14
    # assemble all necessary paths and urls
    drupal_root       = node['deploy-drupal']['deploy_dir']  + "/" +
                        node['deploy-drupal']['project_name'] + "/" +
                        node['deploy-drupal']['drupal_root_dir']
    mysql_root        = "mysql -u root -p#{node['mysql']['server_root_password']} " +
                        "--database=#{node['deploy-drupal']['db_name']}"
    solr_root_url     = "http://localhost:#{node['tomcat']['port']}/" +
                        node['deploy-drupal']['solr']['app_name']
    # this section is a ",' and \ mine field, watch yourself:
    # \&: since & in curl requests will confuse bash as background process indicator
    solr_commit_req   = solr_root_url + 
                        '/update?commit=true\&waitFlush=true\&waitSearcher=true'
    solr_luke_req     = solr_root_url + 
                        '/admin/luke?fl=numDocs\&wt=json'
    # the sed command should end up to be:
    # sed 's/^.*\"numDocs\":\([0-9]\{1,\}\).*$/\1/'
    find_num_docs     = "curl #{solr_luke_req} " +
                        '| sed \'s/^.*\"numDocs\":\([0-9]\{1,\}\).*$/\1/\''
    minitest_log_dir  = "/tmp/minitest/solr"
    drush             = "cd #{drupal_root}; drush"
    
    system "rm -rf #{minitest_log_dir}; mkdir -p #{minitest_log_dir}"
    
    # install devel and enable devel and devel_generate if necessary 
    system "#{drush} dl -n devel;\
            #{drush} en -y devel devel_generate;\
            #{drush} cc all;"
    
    # record number of indexed documents in solr
    system "echo `#{find_num_docs}` > #{minitest_log_dir}/before"
    
    # make sure all existing documents are indexed and commited to solr
    system "#{drush} solr-index; curl #{solr_commit_req}"
    
    # generate content via drush, and record timestamps for cleanup
    before_time = Time.now.getutc.to_i
    system "#{drush} generate-content #{n} 0"
    after_time = Time.now.getutc.to_i
    
    # index new content, and send commit request to solr
    system "#{drush} solr-index; curl #{solr_commit_req}" 
    
    # record the number of indexed documents in solr after new content generation
    system "echo `#{find_num_docs}` > #{minitest_log_dir}/after"
    database_cleanup  = "#{mysql_root} -e \"\
                        DELETE FROM node WHERE \
                        created > #{before_time} AND\
                        created < #{after_time}\""
    Chef::Log.info database_cleanup
    #system database_cleanup 
    new_docs_cmd = "expr $(sed -n 1p #{minitest_log_dir}/after) - $(sed -n 1p #{minitest_log_dir}/before)"
    system "cat #{minitest_log_dir}/after; cat #{minitest_log_dir}/before"
    Chef::Log.info "running: test `#{new_docs_cmd}` -eq #{n}"
    assert_sh "test `#{new_docs_cmd}` -eq #{n}" , "expected Solr to index new content"
  end
end
