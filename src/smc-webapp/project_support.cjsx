###############################################################################
#
# SageMathCloud: A collaborative web-based interface to Sage, IPython, LaTeX and the Terminal.
#
#    Copyright (C) 2016, SageMath, Inc.
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

underscore = require('underscore')
{React, ReactDOM, Actions, Store, rtypes, rclass, Redux}  = require('./smc-react')
{Col, Row, Button, Input, Well, Alert, Modal} = require('react-bootstrap')
{Icon, Loading, SearchInput, Space, ImmutablePureRenderMixin} = require('./r_misc')
misc            = require('smc-util/misc')
misc_page       = require('./misc_page')
{HelpEmailLink, SiteName} = require('./customize')

ProjectSupportInfo = rclass
    displayName : 'ProjectSupport-info'

    propTypes :
        support_state        : rtypes.string.isRequired
        support_url          : rtypes.string.isRequired
        support_err          : rtypes.string.isRequired
        support_filepath     : rtypes.string.isRequired
        support_has_email    : rtypes.bool.isRequired
        show_form            : rtypes.bool.isRequired
        new                  : rtypes.func.isRequired

    error : () ->
        <div style={fontWeight:'bold', fontSize: '120%'}>
            Sorry, there has been an error creating the ticket.
            Please email <HelpEmailLink /> directly!
            <pre>{"ERROR: "} {@props.support_err}</pre>
        </div>

    created : () ->
        if @props.support_url?.length > 1
            url = <a href={@props.support_url} target='_blank'>{@props.support_url}</a>
        else
            url = 'no ticket'
        <div style={textAlign:'center'}>
          <p>
              Ticket has been created successfully.
              Save this link for future reference:
          </p>
          <p style={fontSize:'120%'}>{url}</p>
          <Button bsStyle='success'
              style={marginTop:'3em'}
              onClick={@props.new}>Create New Ticket</Button>
       </div>

    default : () ->
        if @props.support_filepath? and @props.support_filepath.length > 0
            what = ["file ", <code key={1}>{@props.support_filepath}</code>]
        else
            what = "current project"
        <div>
            <p>
                You have a problem in the {what}?
                Tell us about it by creating a support ticket.
            </p>
            <p>
                After successfully submitting it,
                you{"'"}ll receive a ticket number and a link to the ticket.
                Keep it to stay in contact with us!
            </p>
        </div>

    render : ->
        if not @props.support_has_email
            return <p>To get support, you have to specify a valid email address in your account first!</p>
        else
            switch @props.support_state
                when 'error'
                    return @error()
                when 'creating'
                    return <Loading />
                when 'created'
                    return @created()
                else
                    return @default()

ProjectSupportFooter = rclass
    displayName : 'ProjectSupport-footer'

    propTypes :
        close    : rtypes.func.isRequired
        submit   : rtypes.func.isRequired
        show_form: rtypes.bool.isRequired
        valid    : rtypes.bool.isRequired

    render : ->
        if @props.show_form
            btn = <Button bsStyle='primary'
                          onClick={@props.submit}
                          disabled={not @props.valid}>
                       <Icon name='medkit' /> Get Support
                   </Button>
        else
            btn = <span/>

        <Modal.Footer>
            <Button bsStyle='default' onClick={@props.close}>Close</Button>
            {btn}
        </Modal.Footer>

ProjectSupportForm = rclass
    displayName : 'ProjectSupport-form'

    getDefaultProps : ->
        show        : true

    propTypes :
        support_body    : rtypes.string.isRequired
        support_subject : rtypes.string.isRequired
        show            : rtypes.bool.isRequired
        submit          : rtypes.func.isRequired
        actions         : rtypes.object.isRequired

    handle_change : ->
        @props.actions.setState(support_body     : @refs.project_support_body.getValue())
        @props.actions.setState(support_subject  : @refs.project_support_subject.getValue())

    render : ->
        if @props.show
            <form onSubmit={@props.submit}>
                <Input
                    ref         = 'project_support_subject'
                    autoFocus
                    type        = 'text'
                    placeholder = "Subject ..."
                    value       = {@props.support_subject}
                    onChange    = {@handle_change} />
                <Input
                    ref         = 'project_support_body'
                    type        = 'textarea'
                    placeholder = 'Describe the problem ...'
                    rows        = 6
                    value       = {@props.support_body}
                    onChange    = {@handle_change} />
            </form>
        else
            <div />


ProjectSupport = (name) -> rclass
    displayName : 'ProjectSupport-main'

    mixins: [ImmutablePureRenderMixin]

    propTypes :
        actions : rtypes.object.isRequired

    getDefaultProps : ->
        support_show        : false
        support_subject     : ''
        support_body        : ''
        support_state       : ''
        support_url         : ''
        support_err         : ''
        support_filepath    : ''
        support_has_email   : true

    reduxProps :
        "#{name}" :
            support_show         : rtypes.bool
            support_has_email    : rtypes.bool
            support_subject      : rtypes.string
            support_body         : rtypes.string
            support_state        : rtypes.string # '' ←→ {creating → created|error}
            support_url          : rtypes.string
            support_err          : rtypes.string
            support_filepath     : rtypes.string

    open : ->
        @props.actions.show_support_dialog(true)

    close : ->
        @props.actions.show_support_dialog(false)

    submit : (event) ->
        event.preventDefault()
        @props.actions.support()

    new : (event) ->
        @props.actions.support_new_ticket()

    valid : () ->
        s = @props.support_subject.trim() isnt ''
        b = @props.support_body.trim() isnt ''
        return s and b

    render : () ->
        show_form = false

        if @props.support_has_email
            if (not @props.support_state?) or @props.support_state == ''
                show_form = true

        <Modal show={@props.support_show} onHide={@close}>
            <Modal.Header closeButton>
                <Modal.Title>Support Ticket</Modal.Title>
            </Modal.Header>

            <Modal.Body>
                <ProjectSupportInfo
                    support_state     = {@props.support_state}
                    support_url       = {@props.support_url}
                    support_err       = {@props.support_err}
                    support_filepath  = {@props.support_filepath}
                    support_has_email = {@props.support_has_email}
                    new               = {=> @new()}
                    show_form         = {show_form} />
                <ProjectSupportForm
                    support_subject = {@props.support_subject}
                    support_body    = {@props.support_body}
                    show            = {show_form}
                    submit          = {(e) => @submit(e)}
                    actions         = {@props.actions} />
            </Modal.Body>

            <ProjectSupportFooter
                    show_form       = {show_form}
                    close           = {=> @close()}
                    submit          = {(e) => @submit(e)}
                    valid           = {@valid()} />
        </Modal>

render = (project_id, redux) ->
    store   = redux.getProjectStore(project_id)
    actions = redux.getProjectActions(project_id)

    ProjectSupport_connected = ProjectSupport(store.name)

    <Redux redux={redux}>
        <ProjectSupport_connected actions = {actions} />
    </Redux>

exports.render_project_support = (project_id, dom_node, redux) ->
    ReactDOM.render(render(project_id, redux), dom_node)

exports.unmount = unmount = (dom_node) ->
    ReactDOM.unmountComponentAtNode(dom_node)
