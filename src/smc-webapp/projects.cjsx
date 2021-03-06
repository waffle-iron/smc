###############################################################################
#
# SageMathCloud: A collaborative web-based interface to Sage, IPython, LaTeX and the Terminal.
#
#    Copyright (C) 2016, Sagemath Inc.
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
###############################################################################

$          = window.$
immutable  = require('immutable')
underscore = require('underscore')

{salvus_client} = require('./salvus_client')
{alert_message} = require('./alerts')

misc = require('smc-util/misc')
{required, defaults} = misc
{html_to_text} = require('./misc_page')
{SiteName, PolicyPricingPageUrl} = require('./customize')

markdown = require('./markdown')

{Row, Col, Well, Button, ButtonGroup, ButtonToolbar, Grid, FormControl, FormGroup, InputGroup, Alert, Checkbox, Label} = require('react-bootstrap')
{ErrorDisplay, Icon, Loading, LoginLink, ProjectState, Saving, SearchInput, Space , TimeAgo, Tip, UPGRADE_ERROR_STYLE, UpgradeAdjustor, Footer, r_join} = require('./r_misc')
{React, ReactDOM, Actions, Store, Table, redux, rtypes, rclass, Redux}  = require('./smc-react')
{User} = require('./users')
{BillingPageSimplifiedRedux} = require('./billing')
{UsersViewing} = require('./other-users')
{PROJECT_UPGRADES} = require('smc-util/schema')
{redux_name} = require('project_store')

MAX_DEFAULT_PROJECTS = 50

_create_project_tokens = {}

# Define projects actions
class ProjectsActions extends Actions
    set_project_open: (project_id, err) =>
        x = store.get('open_projects')
        index = x.indexOf(project_id)
        if index == -1
            @setState(open_projects : x.push(project_id))

    # Do not call this directly to close a project.  Instead call
    #   redux.getActions('page').close_project_tab(project_id),
    # which calls this.
    set_project_closed: (project_id) =>
        x = store.get('open_projects')
        index = x.indexOf(project_id)
        if index != -1
            redux.removeProjectReferences(project_id)
            @setState(open_projects : x.delete(index))

    # Save all open files in all projects to disk
    save_all_files: () =>
        store.get('open_projects').filter (project_id) =>
            @redux.getProjectActions(project_id).save_all_files()

    # Returns true only if we are a collaborator/user of this project and have loaded it.
    # Should check this before changing anything in the projects table!  Otherwise, bad
    # things will happen.
    have_project: (project_id) =>
        return @redux.getTable('projects')?._table?.get(project_id)?  # dangerous use of _table!

    set_project_title: (project_id, title) =>
        if not @have_project(project_id)
            console.warn("Can't set title -- you are not a collaborator on project '#{project_id}'.")
            return
        if store.get_title(project_id) == title
            # title is already set as requested; nothing to do
            return
        # set in the Table
        @redux.getTable('projects').set({project_id:project_id, title:title})
        # create entry in the project's log
        @redux.getProjectActions(project_id).log
            event : 'set'
            title : title

    set_project_description: (project_id, description) =>
        if not @have_project(project_id)
            console.warn("Can't set description -- you are not a collaborator on project '#{project_id}'.")
            return
        if store.get_description(project_id) == description
            # description is already set as requested; nothing to do
            return
        # set in the Table
        @redux.getTable('projects').set({project_id:project_id, description:description})
        # create entry in the project's log
        @redux.getProjectActions(project_id).log
            event       : 'set'
            description : description

    # Apply default upgrades -- if available -- to the given project.
    # Right now this means upgrading to member hosting and enabling
    # network access.  Later this could mean something else, or be
    # configurable by the user.
    apply_default_upgrades: (opts) =>
        opts = defaults opts,
            project_id : required
        # WARNING/TODO: This may be invalid if redux.getActions('billing')?.update_customer() has
        # not been recently called. There's no big *harm* if it is out of date (since quotas will
        # just get removed when the project is started), but it could be mildly confusing.
        total = redux.getStore('account').get_total_upgrades()
        applied = store.get_total_upgrades_you_have_applied()
        to_upgrade = {}
        for quota in ['member_host', 'network']
            avail = (total[quota] ? 0) - (applied[quota] ? 0)
            if avail > 0
                to_upgrade[quota] = 1
        if misc.len(to_upgrade) > 0
            @apply_upgrades_to_project(opts.project_id, to_upgrade)

    # only owner can set course description.
    set_project_course_info: (project_id, course_project_id, path, pay, account_id, email_address) =>
        if not @have_project(project_id)
            msg = "Can't set description -- you are not a collaborator on project '#{project_id}'."
            alert_message(type:'error', message:msg)
            console.warn(msg)
            return
        course_info = store.get_course_info(project_id)?.toJS()
        if course_info? and course_info.project_id == course_project_id and course_info.path == path and misc.cmp_Date(course_info.pay, pay) == 0 and course_info.account_id == account_id and course_info.email_address == email_address
            # already set as required; do nothing
            return

        # Set in the database (will get reflected in table); setting directly in the table isn't allowed (due to backend schema).
        salvus_client.query
            query :
                projects_owner :
                    project_id : project_id
                    course     :
                        project_id    : course_project_id
                        path          : path
                        pay           : pay
                        account_id    : account_id
                        email_address : email_address

    set_project_course_info_paying: (project_id, cb) =>
        salvus_client.query
            query :
                projects_owner :
                    project_id : project_id
                    course     :
                        paying     : salvus_client.server_time()
            cb : cb

    # Create a new project
    create_project: (opts) =>
        opts = defaults opts,
            title       : 'No Title'
            description : 'No Description'
            token       : undefined  # if given, can use wait_until_project_created
        if opts.token?
            token = opts.token; delete opts.token
            opts.cb = (err, project_id) =>
                _create_project_tokens[token] = {err:err, project_id:project_id}
        salvus_client.create_project(opts)

    # Open the given project
    #TODOJ: should not be in projects...
    # J3: Maybe should be in Page actions? I don't see the upside.
    open_project: (opts) =>
        opts = defaults opts,
            project_id : required  # string  id of the project to open
            target     : undefined # string  The file path to open
            switch_to  : true      # bool    Whether or not to foreground it
        require('./project_store') # registers the project store with redux...
        store = redux.getProjectStore(opts.project_id)
        actions = redux.getProjectActions(opts.project_id)
        relation = redux.getStore('projects').get_my_group(opts.project_id)
        if not relation? or relation in ['public', 'admin']
            @fetch_public_project_title(opts.project_id)
        actions.fetch_directory_listing()
        redux.getActions('page').set_active_tab(opts.project_id) if opts.switch_to
        @set_project_open(opts.project_id)
        if opts.target?
            redux.getProjectActions(opts.project_id)?.load_target(opts.target, opts.switch_to)

    # Clearly should be in top.cjsx
    # tab at old_index taken out and then inserted into the resulting array's new index
    move_project_tab: (opts) =>
        {old_index, new_index, open_projects} = defaults opts,
            old_index : required
            new_index : required
            open_projects: required # immutable

        x = open_projects
        item = x.get(old_index)
        temp_list = x.delete(old_index)
        new_list = temp_list.splice(new_index, 0, item)
        @setState(open_projects:new_list)

    # should not be in projects...?
    load_target: (target, switch_to) =>
        if not target or target.length == 0
            redux.getActions('page').set_active_tab('projects')
            return
        segments = target.split('/')
        if misc.is_valid_uuid_string(segments[0])
            t = segments.slice(1).join('/')
            project_id = segments[0]
            @open_project
                project_id: project_id
                target    : t
                switch_to : switch_to

    # Put the given project in the foreground
    foreground_project: (project_id) =>
        redux.getActions('page').set_active_tab(project_id)

        redux.getStore('projects').wait # the database often isn't loaded at this moment (right when user refreshes)
            until : (store) => store.get_title(project_id)
            cb    : (err, title) =>
                if not err
                    require('./browser').set_window_title(title)  # change title bar

    # Given the id of a public project, make it so that sometime
    # in the future the projects store knows the corresponding title,
    # (at least what it is right now).  For convenience this works
    # even if the project isn't public if the user is an admin, and also
    # works on projects the user owns or collaborats on.
    fetch_public_project_title: (project_id) =>
        @redux.getStore('projects').wait
            until   : (s) => s.get_my_group(@project_id)
            timeout : 60
            cb      : (err, group) =>
                if err
                    group = 'public'
                switch group
                    when 'admin'
                        table = 'projects_admin'
                    when 'owner', 'collaborator'
                        table = 'projects'
                    else
                        table = 'public_projects'
                salvus_client.query
                    query :
                        "#{table}" : {project_id : project_id, title : null}
                    cb    : (err, resp) =>
                        if not err
                            title = resp?.query?[table]?.title
                        title ?= "PRIVATE -- Admin req"
                        @setState(public_project_titles : store.get('public_project_titles').set(project_id, title))

    # If something needs the store to fill in
    #    directory_tree.project_id = {updated:time, error:err, tree:list},
    # call this function.
    fetch_directory_tree: (project_id, opts) =>
        opts = defaults opts,
            exclusions : undefined # Array<String> of sub-trees' root paths to omit
        # WARNING: Do not change the store except in a callback below.
        block = "_fetch_directory_tree_#{project_id}_#{opts.exclusions?.toString()}"
        if @[block]
            return
        @[block] = true
        salvus_client.find_directories
            include_hidden : false
            project_id     : project_id
            exclusions     : opts.exclusions
            cb             : (err, resp) =>
                # ignore calls to update_directory_tree for 5 more seconds
                setTimeout((()=>delete @[block]), 5000)
                x = store.get('directory_trees') ? immutable.Map()
                obj =
                    error   : err
                    tree    : resp?.directories.sort()
                    updated : new Date()
                @setState(directory_trees: x.set(project_id, immutable.fromJS(obj)))

    # The next few actions below involve changing the users field of a project.
    # See the users field of schema.coffee for documentation of the structure of this.

    ###
    # Collaborators
    ###
    remove_collaborator: (project_id, account_id) =>
        salvus_client.project_remove_collaborator
            project_id : project_id
            account_id : account_id
            cb         : (err, resp) =>
                if err # TODO: -- set error in store for this project...
                    err = "Error removing collaborator #{account_id} from #{project_id} -- #{err}"
                    alert_message(type:'error', message:err)

    invite_collaborator: (project_id, account_id) =>
        @redux.getProjectActions(project_id).log
            event    : 'invite_user'
            invitee_account_id : account_id
        salvus_client.project_invite_collaborator
            project_id : project_id
            account_id : account_id
            cb         : (err, resp) =>
                if err # TODO: -- set error in store for this project...
                    err = "Error inviting collaborator #{account_id} from #{project_id} -- #{err}"
                    alert_message(type:'error', message:err)

    invite_collaborators_by_email: (project_id, to, body, subject, silent, replyto, replyto_name) =>
        @redux.getProjectActions(project_id).log
            event         : 'invite_nonuser'
            invitee_email : to
        title = @redux.getStore('projects').get_title(project_id)
        if not body?
            name  = @redux.getStore('account').get_fullname()
            body  = "Please collaborate with me using SageMathCloud on '#{title}'.\n\n\n--\n#{name}"

        link2proj = "https://#{window.location.hostname}/projects/#{project_id}/"

        # convert body from markdown to html, which is what the backend expects
        body = markdown.markdown_to_html(body).s

        salvus_client.invite_noncloud_collaborators
            project_id   : project_id
            title        : title
            link2proj    : link2proj
            replyto      : replyto
            replyto_name : replyto_name
            to           : to
            email        : body
            subject      : subject
            cb           : (err, resp) =>
                if not silent
                    if err
                        alert_message(type:'error', message:err)
                    else
                        alert_message(message:resp.mesg)

    ###
    # Upgrades
    ###
    # - upgrades is a map from upgrade parameters to integer values.
    # - The upgrades get merged into any other upgrades this user may have already applied.
    apply_upgrades_to_project: (project_id, upgrades) =>
        @redux.getTable('projects').set
            project_id : project_id
            users      :
                "#{@redux.getStore('account').get_account_id()}" : {upgrades: upgrades}
                # create entry in the project's log
        # log the change in the project log
        @redux.getProjectActions(project_id).log
            event    : 'upgrade'
            upgrades : upgrades

    clear_project_upgrades: (project_id) =>
        @apply_upgrades_to_project(project_id, misc.map_limit(require('smc-util/schema').DEFAULT_QUOTAS, 0))

    save_project: (project_id) =>
        @redux.getTable('projects').set
            project_id     : project_id
            action_request : {action:'save', time:salvus_client.server_time()}

    start_project: (project_id) ->
        @redux.getTable('projects').set
            project_id     : project_id
            action_request : {action:'start', time:salvus_client.server_time()}

    stop_project: (project_id) =>
        @redux.getTable('projects').set
            project_id     : project_id
            action_request : {action:'stop', time:salvus_client.server_time()}

    close_project_on_server: (project_id) =>  # not used by UI yet - dangerous
        @redux.getTable('projects').set
            project_id     : project_id
            action_request : {action:'close', time:salvus_client.server_time()}

    restart_project: (project_id) ->
        @redux.getTable('projects').set
            project_id     : project_id
            action_request : {action:'restart', time:salvus_client.server_time()}

    # Explcitly set whether or not project is hidden for the given account (state=true means hidden)
    set_project_hide: (account_id, project_id, state) =>
        @redux.getTable('projects').set
            project_id : project_id
            users      :
                "#{account_id}" :
                    hide : !!state

    # Toggle whether or not project is hidden project
    toggle_hide_project: (project_id) =>
        account_id = @redux.getStore('account').get_account_id()
        @redux.getTable('projects').set
            project_id : project_id
            users      :
                "#{account_id}" :
                    hide : not @redux.getStore('projects').is_hidden_from(project_id, account_id)

    delete_project: (project_id) =>
        @redux.getTable('projects').set
            project_id : project_id
            deleted    : true

    # Toggle whether or not project is deleted.
    toggle_delete_project: (project_id) =>
        is_deleted = @redux.getStore('projects').is_deleted(project_id)
        if not is_deleted
            @clear_project_upgrades(project_id)

        @redux.getTable('projects').set
            project_id : project_id
            deleted    : not is_deleted

# Register projects actions
actions = redux.createActions('projects', ProjectsActions)

# Define projects store
class ProjectsStore extends Store
    get_project: (project_id) =>
        return @getIn(['project_map', project_id])?.toJS()

    # Given an array of objects with an account_id field, sort it by the
    # corresponding last_active timestamp for these users on the given project,
    # starting with most recently active.
    # Also, adds the last_active timestamp field to each element of users
    # given their timestamp for activity *on this project*.
    # For global activity (not just on a project) use
    # the sort_by_activity of the users store.
    sort_by_activity: (users, project_id) =>
        last_active = @getIn(['project_map', project_id, 'last_active'])
        if not last_active? # no info
            return users
        for user in users
            user.last_active = last_active.get(user.account_id) ? 0
        # the code below sorts by last-active in reverse order, if defined; otherwise by last name (or as tie breaker)
        last_name = (account_id) =>
            @redux.getStore('users').get_last_name(account_id)

        return users.sort (a,b) =>
            c = misc.cmp(b.last_active, a.last_active)
            if c then c else misc.cmp(last_name(a.account_id), last_name(b.account_id))

    get_users: (project_id) =>
        # return users as an immutable JS map.
        return @getIn(['project_map', project_id, 'users'])

    get_last_active: (project_id) =>
        # return users as an immutable JS map.
        return @getIn(['project_map', project_id, 'last_active'])

    get_title: (project_id) =>
        return @getIn(['project_map', project_id, 'title'])

    get_state: (project_id) =>
        return @getIn(['project_map', project_id, 'state', 'state'])

    get_description: (project_id) =>
        return @getIn(['project_map', project_id, 'description'])

    # Immutable.js info about a student project that is part of a
    # course (will be undefined if not a student project)
    get_course_info: (project_id) =>
        return @getIn(['project_map', project_id, 'course'])

    # If a course payment is required for this project from the signed in user, returns time when
    # it will be required; otherwise, returns undefined.
    date_when_course_payment_required: (project_id) =>
        account = @redux.getStore('account')
        if not account?
            return
        info = @get_course_info(project_id)
        if not info?
            return
        is_student = info?.get?('account_id') == salvus_client.account_id or info?.get?('email_address') == account.get('email_address')
        if is_student and not @is_deleted(project_id)
            # signed in user is the student
            pay = info.get('pay')
            if pay
                if salvus_client.server_time() >= misc.months_before(-3, pay)
                    # It's 3 months after date when sign up required, so course likely over,
                    # and we no longer require payment
                    return
                # payment is required at some point
                if @get_total_project_quotas(project_id)?.member_host
                    # already paid -- thanks
                    return
                else
                    # need to pay, but haven't -- this is the time by which they must pay
                    return pay

    is_deleted: (project_id) =>
        return !!@getIn(['project_map', project_id, 'deleted'])

    is_hidden_from: (project_id, account_id) =>
        return !!@getIn(['project_map', project_id, 'users', account_id, 'hide'])

    get_project_select_list: (current, show_hidden=true) =>
        map = @get('project_map')
        if not map?
            return
        account_id = salvus_client.account_id
        list = []
        if current? and map.has(current)
            list.push(id:current, title:map.get(current).get('title'))
            map = map.delete(current)
        v = map.toArray()
        v.sort (a,b) ->
            if a.get('last_edited') < b.get('last_edited')
                return 1
            else if a.get('last_edited') > b.get('last_edited')
                return -1
            return 0
        others = []
        for i in v
            if not i.deleted and (show_hidden or not i.get('users').get(account_id).get('hide'))
                others.push(id:i.get('project_id'), title:i.get('title'))
        list = list.concat others
        return list

    # Return the group that the current user has on this project, which can be one of:
    #    'owner', 'collaborator', 'public', 'admin' or undefined, where
    # undefined -- means the information needed to determine group hasn't been loaded yet
    # 'owner' - the current user owns the project
    # 'collaborator' - current user is a collaborator on the project
    # 'public' - user is possibly not logged in or is not an admin and not on the project at all
    # 'admin' - user is not owner/collaborator but is an admin, hence has rights
    get_my_group: (project_id) =>
        account_store = @redux.getStore('account')
        if not account_store?
            return
        user_type = account_store.get_user_type()
        if user_type == 'public'
            # Not logged in -- so not in group.
            return 'public'
        if not @get('project_map')? # or @get('project_map').size == 0
        # signed in but waiting for projects store to load
        # If user is part of no projects, doesn't matter anyways
            return
        project = @getIn(['project_map', project_id])
        if not project?
            if account_store.is_admin()
                return 'admin'
            else
                return 'public'
        users = project.get('users')
        me = users?.get(account_store.get_account_id())
        if not me?
            if account_store.is_admin()
                return 'admin'
            else
                return 'public'
        return me.get('group')

    is_project_open: (project_id) =>
        @get('open_projects').includes(project_id)

    wait_until_project_is_open: (project_id, timeout, cb) =>  # timeout in seconds
        @wait
            until   : => @is_project_open(project_id)
            timeout : timeout
            cb      : (err, x) =>
                cb(err or x?.err)

    wait_until_project_exists: (project_id, timeout, cb) =>
        @wait
            until   : => @getIn(['project_map', project_id])?
            timeout : timeout
            cb      : cb

    wait_until_project_created: (token, timeout, cb) =>
        @wait
            until   : =>
                x = _create_project_tokens[token]
                return if not x?
                {project_id, err} = x
                if err
                    return {err:err}
                else
                    if @get('project_map').has(project_id)
                        return {project_id:project_id}
            timeout : timeout
            cb      : (err, x) =>
                if err
                    cb(err)
                else
                    cb(x.err, x.project_id)

    # Returns the total amount of upgrades that this user has allocated
    # across all their projects.
    get_total_upgrades_you_have_applied: =>
        if not @get('project_map')?
            return
        total = {}
        @get('project_map').map (project, project_id) =>
            total = misc.map_sum(total, project.getIn(['users', salvus_client.account_id, 'upgrades'])?.toJS())
        return total

    get_upgrades_you_applied_to_project: (project_id) =>
        return @getIn(['project_map', project_id, 'users', salvus_client.account_id, 'upgrades'])?.toJS()

    # Get the individual users contributions to the project's upgrades
    get_upgrades_to_project: (project_id) =>
        # mapping (or undefined)
        #    {memory:{account_id:1000, another_account_id:2000, ...}, network:{account_id:1, ...}, ...}
        users = @getIn(['project_map', project_id, 'users'])?.toJS()
        if not users?
            return
        upgrades = {}
        for account_id, info of users
            for prop, val of info.upgrades ? {}
                if val > 0
                    upgrades[prop] ?= {}
                    upgrades[prop][account_id] = val
        return upgrades

    # Get the sum of all the upgrades given to the project by all users
    get_total_project_upgrades: (project_id) =>
        # mapping (or undefined)
        #    {memory:3000, network:2, ...}
        users = @getIn(['project_map', project_id, 'users'])?.toJS()
        if not users?
            return
        upgrades = {}
        for account_id, info of users
            for prop, val of info.upgrades ? {}
                upgrades[prop] = (upgrades[prop] ? 0) + val
        return upgrades

    # Get the total quotas for the given project, including free base values and all user upgrades
    get_total_project_quotas: (project_id) =>
        base_values = @getIn(['project_map', project_id, 'settings'])?.toJS()
        if not base_values?
            return
        misc.coerce_codomain_to_numbers(base_values)
        upgrades = @get_total_project_upgrades(project_id)
        return misc.map_sum(base_values, upgrades)

    # Return javascript mapping from project_id's to the upgrades for the given projects.
    # Only includes projects with at least one upgrade
    get_upgraded_projects: =>
        if not @get('project_map')?
            return
        v = {}
        @get('project_map').map (project, project_id) =>
            upgrades = @get_upgrades_to_project(project_id)
            if misc.len(upgrades)
                v[project_id] = upgrades
        return v

    # Return javascript mapping from project_id's to the upgrades the user with the given account_id
    # applied to projects.  Only includes projects that they upgraded that you are a collaborator on.
    get_projects_upgraded_by: (account_id) =>
        if not @get('project_map')?
            return
        account_id ?= salvus_client.account_id
        v = {}
        @get('project_map').map (project, project_id) =>
            upgrades = @getIn(['project_map', project_id, 'users', account_id, 'upgrades'])?.toJS()
            for upgrade,val of upgrades
                if val > 0
                    v[project_id] = upgrades
                    break
        return v

# WARNING: A lot of code relies on the assumption project_map is undefined until it is loaded from the server.
init_store =
    project_map   : undefined   # when loaded will be an immutable.js map that is synchronized with the database
    open_projects : immutable.List()  # ordered list of open projects
    public_project_titles : immutable.Map()

store = redux.createStore('projects', ProjectsStore, init_store)

# Create and register projects table, which gets automatically
# synchronized with the server.
class ProjectsTable extends Table
    query: ->
        return 'projects'

    _change: (table, keys) =>
        actions.setState(project_map: table.get())

redux.createTable('projects', ProjectsTable)

NewProjectCreator = rclass
    displayName : 'Projects-NewProjectCreator'

    propTypes :
        nb_projects : rtypes.number.isRequired

    getInitialState: ->
        state =
            state      : if @props.nb_projects == 0 then 'edit' else 'view'    # view --> edit --> saving --> view
            title_text : ''
            error      : ''

    start_editing: ->
        @setState
            state      : 'edit'
            title_text : ''
        # We also update the customer billing iformation; this is important since
        # we will call apply_default_upgrades in a moment, and it will be more
        # accurate with the latest billing information recently loaded.
        redux.getActions('billing')?.update_customer()

    cancel_editing: ->
        @setState
            state      : 'view'
            title_text : ''
            error      : ''

    toggle_editing: ->
        if @state.state == 'view'
            @start_editing()
        else
            @cancel_editing()

    create_project: (quotas_to_apply) ->
        token = misc.uuid()
        @setState(state:'saving')
        actions.create_project
            title : @state.title_text
            token : token
        store.wait_until_project_created token, 30, (err, project_id) =>
            if err?
                @setState
                    state : 'edit'
                    error : "Error creating project -- #{err}"
            else
                actions.apply_default_upgrades(project_id: project_id)
                actions.open_project(project_id: project_id)


    handle_keypress: (e) ->
        if e.keyCode == 27
            @cancel_editing()
        else if e.keyCode == 13 and @state.title_text != ''
            @create_project()

    render_info_alert: ->
        if @state.state == 'saving'
            <div style={marginTop:'30px'}>
                <Alert bsStyle='info'>Creating project... <Icon name='circle-o-notch' spin /></Alert>
            </div>

    render_error: ->
        if @state.error
            <div style={marginTop:'30px'}>
                <ErrorDisplay error={@state.error} onClose={=>@setState(error:'')} />
            </div>

    render_input_section: ->
        <Well style={backgroundColor: '#FFF'}>
            <Row>
                <Col sm=6>
                    <FormGroup>
                        <FormControl
                            ref         = 'new_project_title'
                            type        = 'text'
                            placeholder = 'Project title'
                            disabled    = {@state.state == 'saving'}
                            value       = {@state.title_text}
                            onChange    = {=>@setState(title_text:ReactDOM.findDOMNode(@refs.new_project_title).value)}
                            onKeyDown   = {@handle_keypress}
                            autoFocus   />
                    </FormGroup>
                    <ButtonToolbar>
                        <Button
                            disabled  = {@state.title_text == '' or @state.state == 'saving'}
                            onClick   = {=>@create_project(false)}
                            bsStyle  = 'success' >
                            Create project
                        </Button>
                        <Button
                            disabled = {@state.state is 'saving'}
                            onClick  = {@cancel_editing} >
                            Cancel
                        </Button>
                    </ButtonToolbar>
                </Col>
                <Col sm=6>
                    <div style={color:'#666'}>
                        A <b>project</b> is your own computational workspace that you can share with others.
                        You can easily change the project title later.
                    </div>
                </Col>
            </Row>
            <Row>
                <Col sm=12>
                    {@render_error()}
                    {@render_info_alert()}
                </Col>
            </Row>
        </Well>

    render: ->
        <Row>
            <Col sm=4>
                <Button
                    bsStyle  = 'success'
                    active   = {@state.state != 'view'}
                    disabled = {@state.state != 'view'}
                    block
                    type     = 'submit'
                    onClick  = {@toggle_editing}>
                    <Icon name='plus-circle' /> Create new project...
                </Button>
            </Col>
            {<Col sm=12>
                <Space/>
                {@render_input_section()}
            </Col> if @state.state != 'view'}
        </Row>

ProjectsFilterButtons = rclass
    displayName : 'ProjectsFilterButtons'

    propTypes :
        hidden              : rtypes.bool.isRequired
        deleted             : rtypes.bool.isRequired
        show_hidden_button  : rtypes.bool
        show_deleted_button : rtypes.bool

    getDefaultProps: ->
        hidden  : false
        deleted : false
        show_hidden_button : false
        show_deleted_button : false

    render_deleted_button: ->
        style = if @props.deleted then 'warning' else "default"
        if @props.show_deleted_button
            <Button onClick={=>@actions('projects').setState(deleted: not @props.deleted)} bsStyle={style}>
                <Icon name={if @props.deleted then 'check-square-o' else 'square-o'} fixedWidth /> Deleted
            </Button>
        else
            return null

    render_hidden_button: ->
        style = if @props.hidden then 'warning' else "default"
        if @props.show_hidden_button
            <Button onClick = {=>@actions('projects').setState(hidden: not @props.hidden)} bsStyle={style}>
                <Icon name={if @props.hidden then 'check-square-o' else 'square-o'} fixedWidth /> Hidden
            </Button>

    render: ->
        <ButtonGroup>
            {@render_deleted_button()}
            {@render_hidden_button()}
        </ButtonGroup>

ProjectsSearch = rclass
    displayName : 'Projects-ProjectsSearch'

    propTypes :
        search : rtypes.string.isRequired

    getDefaultProps: ->
        search             : ''
        open_first_project : undefined

    clear_and_focus_search_input: ->
        @refs.projects_search.clear_and_focus_search_input()

    render: ->
        <SearchInput
            ref         = 'projects_search'
            autoFocus   = {true}
            value       = {@props.search}
            placeholder = 'Search for projects...'
            on_change   = {(value)=>@actions('projects').setState(search: value)}
            on_submit   = {(_, opts)=>@props.open_first_project(not opts.ctrl_down)}
        />

HashtagGroup = rclass
    displayName : 'Projects-HashtagGroup'

    propTypes :
        hashtags          : rtypes.array.isRequired
        toggle_hashtag    : rtypes.func.isRequired
        selected_hashtags : rtypes.object

    getDefaultProps: ->
        selected_hashtags : {}

    render_hashtag: (tag) ->
        color = 'info'
        if @props.selected_hashtags and @props.selected_hashtags[tag]
            color = 'warning'
        <Button key={tag} onClick={=>@props.toggle_hashtag(tag)} bsSize='small' bsStyle={color}>
            {misc.trunc(tag, 60)}
        </Button>

    render: ->
        <ButtonGroup style={maxHeight:'18ex', overflowY:'auto', overflowX:'hidden'}>
            {@render_hashtag(tag) for tag in @props.hashtags}
        </ButtonGroup>

ProjectsListingDescription = rclass
    displayName : 'Projects-ProjectsListingDescription'

    propTypes :
        deleted           : rtypes.bool
        hidden            : rtypes.bool
        selected_hashtags : rtypes.object
        search            : rtypes.string
        nb_projects       : rtypes.number.isRequired
        visible_projects  : rtypes.array
        on_cancel         : rtypes.func

    getDefaultProps: ->
        deleted           : false
        hidden            : false
        selected_hashtags : {}
        search            : ''

    getInitialState: ->
        show_remove_from_all : false

    render_header: ->
        if @props.nb_projects > 0 and (@props.hidden or @props.deleted)
            d = if @props.deleted then 'deleted ' else ''
            h = if @props.hidden then 'hidden ' else ''
            a = if @props.hidden and @props.deleted then ' and ' else ''
            n = @props.visible_projects.length
            desc = "Only showing #{n} #{d}#{a}#{h} #{misc.plural(n, 'project')}"
            <h3 style={color:'#666', wordWrap:'break-word'}>{desc}</h3>

    render_span: (query) ->
        <span>whose title, description or users contain <strong>{query}</strong>
        <Space/><Space/>
        <Button onClick={=>@setState(show_remove_from_all:false); @props.on_cancel()}>
            Cancel
        </Button></span>

    render_alert_message: ->
        query = @props.search.toLowerCase()
        hashtags_string = (name for name of @props.selected_hashtags).join(' ')
        if query != '' and hashtags_string != '' then query += ' '
        query += hashtags_string

        if query != '' or @props.deleted or @props.hidden
            <Alert bsStyle='warning' style={'fontSize':'1.3em'}>
                Only showing<Space/>
                <strong>{"#{if @props.deleted then 'deleted ' else ''}#{if @props.hidden then 'hidden ' else ''}"}</strong>
                projects<Space/>
                {if query isnt '' then @render_span(query)}
                {@render_remove_from_all_button() if @props.visible_projects.length > 0}
                {@render_remove_from_all() if @state.show_remove_from_all}
            </Alert>

    render_remove_from_all_button: ->
        <Button
            className = 'pull-right'
            disabled  = {@state.show_remove_from_all}
            onClick   = {=>@setState(show_remove_from_all:true)}
            >
            <Icon name='user-times'/>  Remove Myself...
        </Button>

    collab_projects: ->
        # Determine visible projects this user does NOT own.
        return (project for project in @props.visible_projects when project.users?[salvus_client.account_id]?.group != 'owner')

    render_remove_from_all: ->
        if @props.visible_projects.length == 0
            return
        v = @collab_projects()
        head = <h4><Icon name='user-times'/>  Remove Myself from Projects</h4>
        if v.length == 0
            <Alert key='remove_all' style={marginTop:'15px'}>
                {head}
                You are the owner of every displayed project.  You can only remove yourself from projects that you do not own.

                <Button onClick={=>@setState(show_remove_from_all:false)} >
                    Cancel
                </Button>
            </Alert>
        else
            if v.length < @props.visible_projects.length
                other = @props.visible_projects.length - v.length
                desc = "You are a collaborator on #{v.length} of the #{@props.visible_projects.length} #{misc.plural(@props.visible_projects.length, 'project')} listed below (you own the other #{misc.plural(other, 'one')})."
            else
                if v.length == 1
                    desc = "You are a collaborator on the one project listed below."
                else
                    desc = "You are a collaborator on ALL of the #{v.length} #{misc.plural(v.length, 'project')} listed below."
            <Alert  style={marginTop:'15px'}>
                {head} {desc}

                <p/>
                Are you sure you want to remove yourself from the {v.length} {misc.plural(v.length, 'project')} listed below that you collaborate on?  <b>You will no longer have access and cannot add yourself back.</b>

                <ButtonToolbar style={marginTop:'15px'}>
                    <Button bsStyle='danger' onClick={@do_remove_from_all}  >
                        <Icon name='user-times'/> Remove myself from {v.length} {misc.plural(v.length, 'project')}
                    </Button>
                    <Button onClick={=>@setState(show_remove_from_all:false)} >
                        Cancel
                    </Button>
                </ButtonToolbar>
            </Alert>

    do_remove_from_all: ->
        for project in @collab_projects()
            @actions('projects').remove_collaborator(project.project_id, salvus_client.account_id)
        @setState(show_remove_from_all:false)

    render: ->
        <div>
            <Space />
            {@render_header()}
            {@render_alert_message()}
        </div>

ProjectRow = rclass
    displayName : 'Projects-ProjectRow'

    propTypes :
        project : rtypes.object.isRequired
        index   : rtypes.number
        redux   : rtypes.object

    getDefaultProps: ->
        user_map : undefined

    render_status: ->
        state = @props.project.state?.state
        if state?
            <span style={color: '#666'}>
                <ProjectState state={state} />
            </span>

    render_last_edited: ->
        try
            <TimeAgo date={(new Date(@props.project.last_edited)).toISOString()} />
        catch e
            console.log("error setting time of project #{@props.project.project_id} to #{@props.project.last_edited} -- #{e}; please report to wstein@gmail.com")

    render_user_list: ->
        other = ({account_id:account_id} for account_id,_ of @props.project.users)
        redux.getStore('projects').sort_by_activity(other, @props.project.project_id)
        users = []
        for i in [0...other.length]
            users.push <User
                           key         = {other[i].account_id}
                           last_active = {other[i].last_active}
                           account_id  = {other[i].account_id}
                           user_map    = {@props.user_map} />
        return r_join(users)

    handle_mouse_down: (e) ->
        @setState
            selection_at_last_mouse_down : window.getSelection().toString()

    handle_click: (e) ->
        if window.getSelection().toString() == @state.selection_at_last_mouse_down
            @open_project_from_list(e)

    open_project_from_list: (e) ->
        @actions('projects').open_project
            project_id : @props.project.project_id
            switch_to  : not(e.which == 2 or (e.ctrlKey or e.metaKey))
        e.preventDefault()

    open_edit_collaborator: (e) ->
        @actions('projects').open_project
            project_id : @props.project.project_id
            switch_to  : not(e.which == 2 or (e.ctrlKey or e.metaKey))
            target     : 'settings'
        e.stopPropagation()

    render: ->
        project_row_styles =
            backgroundColor : if (@props.index % 2) then '#eee' else 'white'
            marginBottom    : 0
            cursor          : 'pointer'
            wordWrap        : 'break-word'

        <Well style={project_row_styles} onClick={@handle_click} onMouseDown={@handle_mouse_down}>
            <Row>
                <Col sm=3 style={fontWeight: 'bold', maxHeight: '7em', overflowY: 'auto'}>
                    <a>{html_to_text(@props.project.title)}</a>
                </Col>
                <Col sm=2 style={color: '#666', maxHeight: '7em', overflowY: 'auto'}>
                    {@render_last_edited()}
                </Col>
                <Col sm=3 style={color: '#666', maxHeight: '7em', overflowY: 'auto'}>
                    {html_to_text(@props.project.description)}
                </Col>
                <Col sm=3 style={maxHeight: '7em', overflowY: 'auto'}>
                    <a onClick={@open_edit_collaborator}>
                        <Icon name='user' style={fontSize: '16pt', marginRight:'10px'}/>
                        {@render_user_list()}
                    </a>
                </Col>
                <Col sm=1>
                    {@render_status()}
                </Col>
            </Row>
        </Well>

ProjectList = rclass
    displayName : 'Projects-ProjectList'

    propTypes :
        projects    : rtypes.array.isRequired
        show_all    : rtypes.bool.isRequired
        redux       : rtypes.object

    getDefaultProps: ->
        projects : []
        user_map : undefined

    show_all_projects: ->
        @actions('projects').setState(show_all : not @props.show_all)

    render_show_all: ->
        if @props.projects.length > MAX_DEFAULT_PROJECTS
            more = @props.projects.length - MAX_DEFAULT_PROJECTS
            <br />
            <Button
                onClick={@show_all_projects}
                bsStyle='info'
                bsSize='large'>
                Show {if @props.show_all then "#{more} less" else "#{more} more"} matching projects...
            </Button>

    render_list: ->
        listing = []
        i = 0
        for project in @props.projects
            if i >= MAX_DEFAULT_PROJECTS and not @props.show_all
                break
            listing.push <ProjectRow
                             project  = {project}
                             user_map = {@props.user_map}
                             index    = {i}
                             key      = {i}
                             redux    = {redux} />
            i += 1

        return listing

    render: ->
        if @props.nb_projects == 0
            <Alert bsStyle='info'>
                You have not created any projects yet.
                Click on "Create a new project" above to start working with <SiteName/>!
            </Alert>
        else
            <div>
                {@render_list()}
                {@render_show_all()}
            </div>

parse_project_tags = (project) ->
    project_information = (project.title + ' ' + project.description).toLowerCase()
    indices = misc.parse_hashtags(project_information)
    return (project_information.substring(i[0], i[1]) for i in indices)

parse_project_search_string = (project, user_map) ->
    search = (project.title + ' ' + project.description).toLowerCase()
    for k in misc.split(search)
        if k[0] == '#'
            tag = k.slice(1).toLowerCase()
            search += " [#{k}] "
    for account_id in misc.keys(project.users)
        if account_id != salvus_client.account_id
            info = user_map?.get(account_id)
            if info?
                search += (' ' + info.get('first_name') + ' ' + info.get('last_name') + ' ').toLowerCase()
    return search

# Returns true if the project should be visible with the given filters selected
project_is_in_filter = (project, hidden, deleted) ->
    account_id = salvus_client.account_id
    if not account_id?
        throw Error('project page should not get rendered until after user sign-in and account info is set')
    return !!project.deleted == deleted and !!project.users?[account_id]?.hide == hidden

exports.ProjectsPage = ProjectsPage = rclass
    displayName : 'Projects-ProjectsPage'

    reduxProps :
        users :
            user_map : rtypes.immutable
        projects :
            project_map       : rtypes.immutable
            hidden            : rtypes.bool
            deleted           : rtypes.bool
            search            : rtypes.string
            selected_hashtags : rtypes.object
            show_all          : rtypes.bool
        billing :
            customer      : rtypes.object

    propTypes :
        redux             : rtypes.object

    getDefaultProps: ->
        project_map       : undefined
        user_map          : undefined
        hidden            : false
        deleted           : false
        search            : ''
        selected_hashtags : {}
        show_all          : false

    componentWillReceiveProps: (next) ->
        if not @props.project_map?
            return
        # Only update project_list if the project_map actually changed.  Other
        # props such as the filter or search string might have been set,
        # but not the project_map.  This avoids recomputing any hashtag, search,
        # or possibly other derived cached data.
        if not immutable.is(@props.project_map, next.project_map)
            @update_project_list(@props.project_map, next.project_map, next.user_map)
            projects_changed = true
        # Update the hashtag list if the project_map changes *or* either
        # of the filters change.
        if projects_changed or @props.hidden != next.hidden or @props.deleted != next.deleted
            @update_hashtags(next.hidden, next.deleted)
        # If the user map changes, update the search info for the projects with
        # users that changed.
        if not immutable.is(@props.user_map, next.user_map)
            @update_user_search_info(@props.user_map, next.user_map)

    _compute_project_derived_data: (project, user_map) ->
        #console.log("computing derived data of #{project.project_id}")
        # compute the hashtags
        project.hashtags = parse_project_tags(project)
        # compute the search string
        project.search_string = parse_project_search_string(project, user_map)
        return project

    update_user_search_info: (user_map, next_user_map) ->
        if not user_map? or not next_user_map? or not @_project_list?
            return
        for project in @_project_list
            for account_id,_ of project.users
                if not immutable.is(user_map?.get(account_id), next_user_map?.get(account_id))
                    @_compute_project_derived_data(project, next_user_map)
                    break

    update_project_list: (project_map, next_project_map, user_map) ->
        user_map ?= @props.user_map   # if user_map is not defined, use last known one.
        if not project_map?
            # can't do anything without these.
            return
        if next_project_map? and @_project_list?
            # Use the immutable next_project_map to tell the id's of the projects that changed.
            next_project_list = []
            # Remove or modify existing projects
            for project in @_project_list
                id = project.project_id
                next = next_project_map.get(id)
                if next?
                    if project_map.get(id).equals(next)
                        # include as-is in new list
                        next_project_list.push(project)
                    else
                        # include new version with derived data in list
                        next_project_list.push(@_compute_project_derived_data(next.toJS(), user_map))
            # Include newly added projects
            next_project_map.map (project, id) =>
                if not project_map.get(id)?
                    next_project_list.push(@_compute_project_derived_data(project.toJS(), user_map))
        else
            next_project_list = (@_compute_project_derived_data(project.toJS(), user_map) for project in project_map.toArray())

        @_project_list = next_project_list
        # resort by when project was last edited. (feature idea: allow sorting by title or description instead)
        return @_project_list.sort((p0, p1) -> -misc.cmp(p0.last_edited, p1.last_edited))

    project_list: ->
        return @_project_list ? @update_project_list(@props.project_map)

    update_hashtags: (hidden, deleted) ->
        tags = {}
        for project in @project_list()
            if project_is_in_filter(project, hidden, deleted)
                for tag in project.hashtags
                    tags[tag] = true
        @_hashtags = misc.keys(tags).sort()
        return @_hashtags

    # All hashtags of projects in this filter
    hashtags: ->
        return @_hashtags ? @update_hashtags(@props.hidden, @props.deleted)

    # Takes a project and a list of search terms, returns true if all search terms exist in the project
    matches: (project, search_terms) ->
        project_search_string = project.search_string
        for word in search_terms
            if word[0] == '#'
                word = '[' + word + ']'
            if project_search_string.indexOf(word) == -1
                return false
        return true

    visible_projects: ->
        selected_hashtags = underscore.intersection(misc.keys(@props.selected_hashtags[@filter()]), @hashtags())
        words = misc.split(@props.search.toLowerCase()).concat(selected_hashtags)
        return (project for project in @project_list() when project_is_in_filter(project, @props.hidden, @props.deleted) and @matches(project, words))

    toggle_hashtag: (tag) ->
        selected_hashtags = @props.selected_hashtags
        filter = @filter()
        if not selected_hashtags[filter]
            selected_hashtags[filter] = {}
        if selected_hashtags[filter][tag]
            # disable the hashtag
            delete selected_hashtags[filter][tag]
        else
            # enable the hashtag
            selected_hashtags[filter][tag] = true
        @actions('projects').setState(selected_hashtags: selected_hashtags)

    filter: ->
        "#{@props.hidden}-#{@props.deleted}"

    render_projects_title: ->
        projects_title_styles =
            color        : '#666'
            fontSize     : '24px'
            fontWeight   : '500'
            marginBottom : '1ex'
        <div style={projects_title_styles}><Icon name='thumb-tack' /> Projects </div>

    open_first_project: (switch_to=true) ->
        project = @visible_projects()[0]
        if project?
            @actions('projects').setState(search : '')
            @actions('projects').open_project(project_id: project.project_id, switch_to: switch_to)
    ###
    # Consolidate the next two functions.
    ###

    # Returns true if the user has any hidden projects
    has_hidden_projects: ->
        for project in @project_list()
            if project_is_in_filter(project, true, false) or project_is_in_filter(project, true, true)
                return true
        return false


    # Returns true if this project has any deleted files
    has_deleted_projects: ->
        for project in @project_list()
            if project_is_in_filter(project, false, true) or project_is_in_filter(project, true, true)
                return true
        return false

    clear_filters_and_focus_search_input: ->
        @actions('projects').setState(selected_hashtags:{})
        @refs.search.clear_and_focus_input()

    render: ->
        if not @props.project_map?
            if redux.getStore('account')?.get_user_type() == 'public'
                return <LoginLink />
            else
                return <div style={fontSize:'40px', textAlign:'center', color:'#999999'} > <Loading />  </div>

        visible_projects = @visible_projects()
        <div className='container-content'>
            <Grid fluid className='constrained' style={minHeight:"75vh"}>
                <Well style={marginTop:'1em',overflow:'hidden'}>
                    <Row>
                        <Col sm=4>
                            {@render_projects_title()}
                        </Col>
                        <Col sm=4>
                            <ProjectsFilterButtons
                                hidden  = {@props.hidden}
                                deleted = {@props.deleted}
                                show_hidden_button = {@has_hidden_projects() or @props.hidden}
                                show_deleted_button = {@has_deleted_projects() or @props.deleted} />
                        </Col>
                        <Col sm=4>
                            <UsersViewing style={width:'100%'}/>
                        </Col>
                    </Row>
                    <Row>
                        <Col sm=4>
                            <ProjectsSearch ref="search" search={@props.search} open_first_project={@open_first_project} />
                        </Col>
                        <Col sm=8>
                            <HashtagGroup
                                hashtags          = {@hashtags()}
                                selected_hashtags = {@props.selected_hashtags[@filter()]}
                                toggle_hashtag    = {@toggle_hashtag} />
                        </Col>
                    </Row>
                    <Row>
                        <Col sm=12 style={marginTop:'1ex'}>
                            <NewProjectCreator
                                nb_projects = {@project_list().length}
                                />
                        </Col>
                    </Row>
                    <Row>
                        <Col sm=12>
                            <ProjectsListingDescription
                                nb_projects       = {@project_list().length}
                                visible_projects  = {visible_projects}
                                hidden            = {@props.hidden}
                                deleted           = {@props.deleted}
                                search            = {@props.search}
                                selected_hashtags = {@props.selected_hashtags[@filter()]}
                                on_cancel         = {@clear_filters_and_focus_search_input}
                            />
                        </Col>
                    </Row>
                    <Row>
                        <Col sm=12>
                            <ProjectList
                                projects    = {visible_projects}
                                show_all    = {@props.show_all}
                                user_map    = {@props.user_map}
                                redux       = {redux} />
                        </Col>
                    </Row>
                </Well>
            </Grid>
            <Footer/>
        </div>

exports.ProjectTitle = ProjectTitle = rclass
    displayName: 'Projects-ProjectTitle'

    reduxProps:
        projects :
            project_map : rtypes.immutable

    propTypes:
        project_id   : rtypes.string.isRequired
        handle_click : rtypes.func
        style        : rtypes.object

    shouldComponentUpdate: (nextProps) ->
        nextProps.project_map?.get(@props.project_id)?.get('title') != @props.project_map?.get(@props.project_id)?.get('title')

    render: ->
        if not @props.project_map?
            return <Loading />
        title = @props.project_map?.get(@props.project_id)?.get('title')
        if title?
            <a onClick={@props.handle_click} style={@props.style} role='button'>{html_to_text(title)}</a>
        else
            <span style={@props.style}>(Private project)</span>

exports.ProjectTitleAuto = rclass
    displayName: 'Projects-ProjectTitleAuto'

    propTypes:
        project_id : rtypes.string.isRequired
        style      : rtypes.object

    handle_click: ->
        @actions('projects').open_project(project_id : @props.project_id)

    render: ->
        <Redux redux={redux}>
            <ProjectTitle style={@props.style} project_id={@props.project_id} handle_click={@handle_click} />
        </Redux>