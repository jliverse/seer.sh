#seer.sh

For developers and administrators who work with multiple Oracle databases, Seer is a shell script for UNIX machines that quickly runs queries and scripts with SQL*Plus. Unlike industrial tools and environments with up-front configurations, seer.sh takes options and arguments you provide from your favorite shell prompt and runs your queries in a consistent manner so you can generate reports, pipe the output to another command, save the results to a file or automate database administration tasks.

##Usage
    Seer 0.1, a SQL*Plus convenience script for Oracle.
  
    Usage: seer [options...] <filename>
           seer [options...] <SQL statement>
       
    Options:
      -u, --user USER       set the login user to USER
          --password PASS   set the login password to USER
          --pass PASS
      -w, --expect-password wait for the password to be entered interactively
  
      -h, --host HOST       set the Oracle hostname to HOST     (default: localhost)
      -p, --post POST       set the Oracle port to PORT         (default: 1521)
      -s, --sid SID         set the Oracle SID to SID           (default: orcl)
      -n, --service NAME    set the Oracle service name to NAME

      -v, --verbose         print additional output

##Examples

       $ seer "desc TAB"
       $ seer my-sql-script.sql
       $ seer -w -u myusername my-sql-script.sql
       $ seer -h localhost -p 1521 -s orcl -u myusername --password mypassword "select * from TAB"
