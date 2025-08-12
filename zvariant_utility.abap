*&---------------------------------------------------------------------*
*& Report ZVARIANT_UTILITY
*&---------------------------------------------------------------------*
*& Program variants export utility
*& With this program you can query program variants and print them
*& on hierarchy report with drill-down to variant editor or export to a
*& JSON file. From the report, it is also possible to export to Excel.
*&---------------------------------------------------------------------*

REPORT zvariant_utility.

TYPES:
  BEGIN OF ty_variants,
    report     TYPE varid-report,
    variant    TYPE varid-variant,
    vtext      TYPE varit-vtext,
    environmnt TYPE varid-environmnt,
    version    TYPE varid-version,
    ename      TYPE varid-ename,
    edat       TYPE varid-edat,
    etime      TYPE varid-etime,
    aename     TYPE varid-aename,
    aedat      TYPE varid-aedat,
    aetime     TYPE varid-aetime,
    valutab    TYPE rsparams_tt,
  END OF ty_variants,
  tt_variants TYPE STANDARD TABLE OF ty_variants.

TYPES:
  BEGIN OF ty_valutab,
    report  TYPE varid-report,
    variant TYPE varid-variant.
    INCLUDE TYPE rsparams.
TYPES:
  END OF ty_valutab,
  tt_valutab TYPE STANDARD TABLE OF ty_valutab.


DATA:
  gv_program_name TYPE sy-repid,
  gt_variants     TYPE tt_variants,
  gt_valutab      TYPE tt_valutab.


**********************************************************************
* Event handler class
**********************************************************************

CLASS lcl_handle_events DEFINITION.

  PUBLIC SECTION.
    METHODS:

      on_double_click FOR EVENT double_click OF cl_salv_events_hierseq
        IMPORTING level row column.

ENDCLASS.

CLASS lcl_handle_events IMPLEMENTATION.

  METHOD on_double_click.

    IF level EQ 1.
      " Display the selected variant in the editor
      DATA(ls_data) = VALUE #( gt_variants[ row ] OPTIONAL ).
      IF ls_data IS NOT INITIAL.
        CALL FUNCTION 'RS_VARIANT_DISPLAY'
          EXPORTING
            report               = ls_data-report
            variant              = ls_data-variant
          EXCEPTIONS
            no_report            = 1
            report_not_existent  = 2
            report_not_supplied  = 3
            variant_not_existent = 4
            variant_not_supplied = 5
            variant_protected    = 6
            variant_obsolete     = 7
            OTHERS               = 8.
        IF sy-subrc NE 0.
          MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
            WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
        ENDIF.
      ENDIF.
    ENDIF.

  ENDMETHOD.                    "on_double_click

ENDCLASS.


**********************************************************************
* Selection Screen
**********************************************************************

SELECTION-SCREEN BEGIN OF BLOCK b1 WITH FRAME TITLE TEXT-001.
  PARAMETERS: p_prog TYPE varid-report OBLIGATORY.
SELECTION-SCREEN END OF BLOCK b1.

SELECTION-SCREEN BEGIN OF BLOCK b2 WITH FRAME TITLE TEXT-002.
  PARAMETERS: p_alv  RADIOBUTTON GROUP rg1 DEFAULT 'X',
              p_json RADIOBUTTON GROUP rg1,
              p_test AS CHECKBOX.
SELECTION-SCREEN END OF BLOCK b2.

**********************************************************************
START-OF-SELECTION.
**********************************************************************

  gv_program_name = p_prog.
  PERFORM read_variants.


  IF lines( gt_variants ) EQ 0.
    MESSAGE 'No variants found for program' && | | && gv_program_name TYPE 'I'.
    RETURN.
  ENDIF.

  MESSAGE |Found { lines( gt_variants ) } variants for program { gv_program_name }| TYPE 'S'.

  CASE abap_true.
    WHEN p_alv.
      PERFORM print_hier_report.
    WHEN p_json.
      PERFORM export_to_json.
  ENDCASE.

**********************************************************************
* Subroutines
**********************************************************************

FORM read_variants.

  DATA:
    lt_valutab TYPE STANDARD TABLE OF rsparams,
    lt_objects TYPE STANDARD TABLE OF vanz.


  SELECT v~report,
         v~variant,
         t~vtext,
         v~environmnt,
         v~version,
         v~ename,
         v~edat,
         v~etime,
         v~aename,
         v~aedat,
         v~aetime
    FROM varid AS v
    JOIN varit AS t
    ON   t~langu   EQ @sy-langu
    AND  t~report  EQ v~report
    AND  t~variant EQ v~variant
    INTO CORRESPONDING FIELDS OF TABLE @gt_variants
    WHERE v~report EQ @p_prog.

  SORT gt_variants BY report variant.

  LOOP AT gt_variants REFERENCE INTO DATA(lo_variant).

    CALL FUNCTION 'RS_VARIANT_CONTENTS'
      EXPORTING
        report               = lo_variant->report
        variant              = lo_variant->variant
      TABLES
        valutab              = lt_valutab
        objects              = lt_objects
      EXCEPTIONS
        variant_non_existent = 1
        variant_obsolete     = 2
        OTHERS               = 3.
    IF sy-subrc EQ 0.

      lo_variant->valutab[] = lt_valutab[].

      LOOP AT lt_valutab INTO DATA(ls_valutab).
        APPEND INITIAL LINE TO gt_valutab REFERENCE INTO DATA(lo_valutab).
        lo_valutab->* = CORRESPONDING #( ls_valutab ).
        lo_valutab->report  = lo_variant->report.
        lo_valutab->variant = lo_variant->variant.
      ENDLOOP.
    ENDIF.

    REFRESH: lt_valutab, lt_objects.
  ENDLOOP.

ENDFORM.

FORM print_hier_report.

  DATA:
    lo_hier_alv TYPE REF TO cl_salv_hierseq_table,
    lt_binding  TYPE salv_t_hierseq_binding,
    lo_events   TYPE REF TO lcl_handle_events.


  lt_binding = VALUE #(
                        ( master = 'REPORT'  slave = 'REPORT' )
                        ( master = 'VARIANT' slave = 'VARIANT' )
                      ).

  TRY.
      cl_salv_hierseq_table=>factory(
        EXPORTING
          t_binding_level1_level2 = lt_binding
        IMPORTING
          r_hierseq               = lo_hier_alv
        CHANGING
          t_table_level1          = gt_variants
          t_table_level2          = gt_valutab
      ).

      DATA(lo_columns_master) = lo_hier_alv->get_columns( level = 1 ).
      lo_columns_master->get_column( 'ENAME' )->set_medium_text( 'Created by' ).
      lo_columns_master->get_column( 'EDAT' )->set_medium_text( 'Created on' ).
      lo_columns_master->get_column( 'ETIME' )->set_medium_text( 'Cr.time' ).

      lo_columns_master->get_column( 'AENAME' )->set_medium_text( 'Changed by' ).
      lo_columns_master->get_column( 'AEDAT' )->set_medium_text( 'Changed on' ).
      lo_columns_master->get_column( 'AETIME' )->set_medium_text( 'Ch.time' ).

      " Hide parent fields from the 2nd level
      DATA(lo_columns_slave) = lo_hier_alv->get_columns( level = 2 ).
      lo_columns_slave->get_column( 'REPORT' )->set_visible( abap_false ).
      lo_columns_slave->get_column( 'VARIANT' )->set_visible( abap_false ).

      lo_hier_alv->get_functions_base( )->set_all( ).

      DATA(lo_event) = lo_hier_alv->get_event( ).

      CREATE OBJECT lo_events.
      SET HANDLER lo_events->on_double_click FOR lo_event.

      lo_hier_alv->display( ).


    CATCH cx_salv_data_error INTO DATA(lx_msg1).
      MESSAGE lx_msg1->get_text( ) TYPE 'E'.
    CATCH cx_salv_not_found INTO DATA(lx_msg2).
      MESSAGE lx_msg2->get_text( ) TYPE 'E'.
  ENDTRY.

ENDFORM.

FORM export_to_json.

  DATA:
    lt_files    TYPE filetable,
    lv_filename TYPE string,
    lv_fullpath TYPE string,
    lv_path     TYPE string,
    lt_string   TYPE TABLE OF string.


  CHECK gt_variants IS NOT INITIAL.

  " Convert data to JSON string
  DATA(lv_json) = /ui2/cl_json=>serialize(
    data        = gt_variants
    pretty_name = /ui2/cl_json=>pretty_mode-camel_case
  ).

  IF p_test EQ abap_true.
    " Preview JSON data
    cl_demo_output=>display_json( lv_json ).
    RETURN.
  ENDIF.

  " Prompt for a file name for saving
  cl_gui_frontend_services=>file_save_dialog(
    EXPORTING
      window_title              = 'Save as JSON file'
      default_extension         = 'json'
      default_file_name         = lv_filename
      file_filter               = 'JSON file (*.json)|*.json'
      initial_directory         = ''
      prompt_on_overwrite       = 'X'
    CHANGING
      filename                  = lv_filename
      path                      = lv_path
      fullpath                  = lv_fullpath
    EXCEPTIONS
      cntl_error                = 1
      error_no_gui              = 2
      not_supported_by_gui      = 3
      invalid_default_file_name = 4
      OTHERS                    = 5
  ).
  IF sy-subrc NE 0.
    MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
      WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
  ENDIF.

  IF lv_fullpath IS NOT INITIAL.

    IF lv_fullpath NS '.json'.
      lv_fullpath = |{ lv_fullpath }.json|.
    ENDIF.

    APPEND lv_json TO lt_string.

    " Write JSON data into a local file
    cl_gui_frontend_services=>gui_download(
      EXPORTING
        filename                = lv_fullpath
        filetype                = 'ASC'
      CHANGING
        data_tab                = lt_string
      EXCEPTIONS
        file_write_error        = 1
        no_batch                = 2
        gui_refuse_filetransfer = 3
        invalid_type            = 4
        no_authority            = 5
        unknown_error           = 6
        header_not_allowed      = 7
        separator_not_allowed   = 8
        filesize_not_allowed    = 9
        header_too_long         = 10
        dp_error_create         = 11
        dp_error_send           = 12
        dp_error_write          = 13
        unknown_dp_error        = 14
        access_denied           = 15
        dp_out_of_memory        = 16
        disk_full               = 17
        dp_timeout              = 18
        file_not_found          = 19
        dataprovider_exception  = 20
        control_flush_error     = 21
        not_supported_by_gui    = 22
        error_no_gui            = 23
        OTHERS                  = 24
    ).
    IF sy-subrc NE 0.
      MESSAGE ID sy-msgid TYPE sy-msgty NUMBER sy-msgno
        WITH sy-msgv1 sy-msgv2 sy-msgv3 sy-msgv4.
    ENDIF.
  ENDIF.

ENDFORM.
