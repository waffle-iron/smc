###
Top-level react component, which ties everything together

###

{ErrorDisplay, Icon, Loading} = require('../r_misc')

misc_page = require('../misc_page')

{React, ReactDOM, rclass, rtypes}  = require('../smc-react')

# React components that implement parts of the Jupyter notebook.

{InputEditor}  = require('./input')
{TopMenubar}   = require('./top-menubar')
{TopButtonbar} = require('./top-buttonbar')

exports.JupyterEditor = rclass ({name}) ->
    propTypes :
        error      : rtypes.string
        actions    : rtypes.object.isRequired

    reduxProps :
        "#{name}" :
            kernel    : rtypes.string          # string name of the kernel
            cells     : rtypes.immutable.Map   # map from id to cells
            cell_list : rtypes.immutable.List  # list of ids of cells in order

            cur_id    : rtypes.string          # id of currently selected cell
            sel_ids   : rtypes.immutable.Set   # set of selected cells
            mode      : rtypes.string          # 'edit' or 'escape'
            error     : rtypes.string

    render_error: ->
        if @props.error
            <ErrorDisplay
                error = {@props.error}
                onClose = {=>@props.actions.set_error(undefined)}
            />

    render_kernel: ->
        <div className='pull-right' style={color:'#666'}>
            Python 2 (SageMath)
        </div>

    render_menubar: ->
        <TopMenubar actions = {@props.actions} />

    render_buttonbar: ->
        <TopButtonbar actions = {@props.actions} />

    render_heading: ->
        <div style={boxShadow: '0px 0px 12px 1px rgba(87, 87, 87, 0.2)', zIndex: 100}>
            {@render_menubar()}
            {@render_kernel()}
            {@render_buttonbar()}
        </div>

    render_cell_input: (cell, cm_options) ->
        id = cell.get('id')
        <div key='in' style={display: 'flex', flexDirection: 'row', alignItems: 'stretch'}>
            <div style={color:'#303F9F', minWidth: '14ex', fontFamily: 'monospace', textAlign:'right', padding:'.4em'}>
                In [{cell.get('number') ? '*'}]:
            </div>
            <InputEditor
                value    = {cell.get('input') ? ''}
                options  = {cm_options}
                actions  = {@props.actions}
                id       = {id}
            />
        </div>

    render_output_number: (n) ->
        if not n
            return
        <span>
            Out[{n}]:
        </span>

    render_cell_output: (cell) ->
        if not cell.get('output')?
            return
        n = cell.get('number')
        <div key='out'  style={display: 'flex', flexDirection: 'row', alignItems: 'stretch'}>
            <div style={color:'#D84315', minWidth: '14ex', fontFamily: 'monospace', textAlign:'right', padding:'.4em', paddingBottom:0}>
                {@render_output_number(n)}
            </div>
            <pre style={width:'100%', backgroundColor: '#fff', border: 0, padding: '9.5px 9.5px 0 0', marginBottom:0}>
                {cell.get('output') ? ''}
            </pre>
        </div>

    click_on_cell: (id, event) ->
        if event.shiftKey
            misc_page.clear_selection()
            @props.actions.select_cell_range(id)
        else
            @props.actions.set_cur_id(id)
            @props.actions.unselect_all_cells()

    render_cell: (id, cm_options) ->
        selected = @props.sel_ids?.contains(id)
        if @props.cur_id == id
            # currently selected cell
            if @props.mode == 'edit'
                # edit mode
                color1 = color2 = '#66bb6a'
            else
                # escape mode
                color1 = '#ababab'
                color2 = '#42a5f5'
        else
            if selected
                color1 = color2 = '#e3f2fd'
            else
                color1 = color2 = 'white'
        style =
            border          : "1px solid #{color1}"
            borderLeft      : "5px solid #{color2}"
            padding         : '5px'

        if selected
            style.background = '#e3f2fd'

        cell = @props.cells.get(id)
        <div key={id} style={style} onClick={(e) =>@click_on_cell(id, e)}>
            {@render_cell_input(cell, cm_options)}
            {@render_cell_output(cell)}
        </div>

    render_cells: ->
        cm_options =
            indentUnit        : 4
            matchBrackets     : true
            autoCloseBrackets : true
            mode              :
                name                   : "python"
                version                : 3
                singleLineStringErrors : false

        v = []
        @props.cell_list.map (id) =>
            v.push @render_cell(id, cm_options)
            return
        <div key='cells' style={paddingLeft:'20px', padding:'20px',  backgroundColor:'#eee', height: '100%', overflowY:'auto'}>
            <div style={backgroundColor:'#fff', padding:'15px', boxShadow: '0px 0px 12px 1px rgba(87, 87, 87, 0.2)'}>
                {v}
            </div>
        </div>

    render: ->
        if not @props.cells? or not @props.cell_list?
            return <Loading/>
        <div style={display: 'flex', flexDirection: 'column', height: '100%', overflowY:'hidden'}>
            {@render_error()}
            {@render_heading()}
            {@render_cells()}
        </div>
