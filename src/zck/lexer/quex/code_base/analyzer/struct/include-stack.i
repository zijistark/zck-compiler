/* -*- C++ -*- vim:set syntax=cpp:
 *
 * INCLUSION: Include lexical analysis of a new input stream.
 *
 * The current state of the lexical analyzer is stored on a stack in a
 * 'memento'. Then, it is initialized for analysis of the new input stream.
 * When the new input stream terminates, the memento is popped from the stack
 * and the according state is re-established. This process of 'nesting
 * analysis' may be used recursively.
 *
 * PUSH: 'include'
 *
 *   -- Takes over any OWNERSHIP! 
 *   -- Include may fail, but it never throws an exception!
 *      Failure is notified by the '.error_code' flag.
 *   -- '.receive()' may always be called, but that function might return
 *      immediately if '.error_code' is not 'NONE'.
 *   -- The destructor can be called safely for any object that has been 
 *      'included'--even if the inclusion failed.
 *
 * FAILURE => Current lexical analyzer object remains as it is!
 *            Overtaken objects are deleted!
 *
 * POP: 'return from include'
 *
 *   -- never fails, never throws exceptions.
 *
 *______________________________________________________________________________
 * INSIGHT: 
 *
 *    The process of 'include_push' consists of two major phases:
 * 
 *    (1) New resources are allocated. In that phases FAILURES MAY OCCUR. 
 *        If errors occur, the lexer is still UNTOUCHED!
 *
 *    (2) All allocation has been done. SUCCESS IS GRANTED. 
 *        Only then, the lexer object is assigned new content.
 * 
 * The *pivot point* of 'success granted' is inside the function 
 * 'include_push_core()'. If it returns != NULL, success is granted.
 * Anything that might fail, *must happen before* the call to this function.
 * The exact 'pivot point' is marked in a comment by '[PIVOT POINT]'.
 *______________________________________________________________________________
 *
 * (C) 2004-2017 Frank-Rene Schaefer
 *____________________________________________________________________________*/
#ifndef  __QUEX_INCLUDE_GUARD__ANALYZER__STRUCT__INCLUDE_STACK_I
#define  __QUEX_INCLUDE_GUARD__ANALYZER__STRUCT__INCLUDE_STACK_I

/*  __QUEX_INCLUDE_GUARD__ANALYZER__STRUCT__INCLUDE_STACK_I may be undefined in case
 *    that multiple lexical analyzers are used. Then, the name of the
 *    QUEX_NAME(Accumulator) must be different.                               */
#ifndef   QUEX_TYPE_ANALYZER
#   error "Macro QUEX_TYPE_ANALYZER must be defined before inclusion of this file."
#endif


QUEX_NAMESPACE_MAIN_OPEN

QUEX_INLINE bool
QUEX_NAME(Memento_construct)(QUEX_NAME(Memento)* memento,
                             QUEX_TYPE_ANALYZER* me,
                             const char*         InputNameP);

QUEX_INLINE bool
QUEX_NAME(include_push_file_name)(QUEX_TYPE_ANALYZER*     me,
                                  const char*             FileName, 
                                  QUEX_NAME(Converter)*   new_converter /* = 0 */)
{
    QUEX_NAME(ByteLoader)*  new_byte_loader;

    new_byte_loader = QUEX_NAME(ByteLoader_FILE_new_from_file_name)(FileName);
    if( ! new_byte_loader ) {
        QUEX_NAME(error_code_set_if_first)(me, E_Error_File_OpenFailed);
        goto ERROR_0;
    }
    else if( ! QUEX_NAME(include_push_ByteLoader)(me, FileName, new_byte_loader, new_converter) ) {
        goto ERROR_1;
    }
    return true;

    /* ERROR CASES: Free Resources ___________________________________________*/
ERROR_0:
    if( new_converter) new_converter->delete_self(new_converter);
ERROR_1:
    /* All resource freeing is done in called functions.                      */
    return false;
}

/* USE: byte_loader = QUEX_NAME(ByteLoader_FILE_new)(fh, BinaryModeF);
 *      byte_loader = QUEX_NAME(ByteLoader_stream_new)(istream_p, BinaryModeF);
 *      byte_loader = QUEX_NAME(ByteLoader_wstream_new)(wistream_p, BinaryModeF);
 *      ...
 *      Unit Test's StrangeStreams:
 *      byte_loader = QUEX_NAME(ByteLoader_stream_new)(strangestr_p, false);  */
QUEX_INLINE bool
QUEX_NAME(include_push_ByteLoader)(QUEX_TYPE_ANALYZER*     me,
                                   const char*             InputName,
                                   QUEX_NAME(ByteLoader)*  new_byte_loader,
                                   QUEX_NAME(Converter)*   new_converter /* = 0 */)
{
    QUEX_NAME(LexatomLoader)* new_filler;

    new_filler = QUEX_NAME(LexatomLoader_new)(new_byte_loader, new_converter);
    if( ! new_filler ) {
        QUEX_NAME(error_code_set_if_first)(me, E_Error_Allocation_LexatomLoader_Failed);
        goto ERROR_0;
    }
    else if( me->buffer.filler )
    {
        /* Overtake the byte order reversion behavior of including filler.    */                                                
        new_filler->_byte_order_reversion_active_f = \
                              me->buffer.filler->_byte_order_reversion_active_f;
    }

    if( ! QUEX_NAME(include_push_core)(me, InputName, (QUEX_NAME(Buffer)*)0,
                                       new_filler) ) {
        goto ERROR_1;
    }
    return true;

    /* ERROR CASES: Free Resources ___________________________________________*/
ERROR_1:
    if( new_filler ) new_filler->delete_self(new_filler);
    return false;
ERROR_0:
    if( new_byte_loader ) new_byte_loader->delete_self(new_byte_loader);
    if( new_converter )   new_converter->delete_self(new_converter);
    return false;
}

QUEX_INLINE bool
QUEX_NAME(include_push_memory)(QUEX_TYPE_ANALYZER* me,
                               const char*         InputName,
                               QUEX_TYPE_LEXATOM*  Memory,
                               const size_t        MemorySize,
                               QUEX_TYPE_LEXATOM*  EndOfFileP)
/* When memory is provided from extern, the 'external entity' is
 * responsible for filling it. There is no 'file/stream handle', no 'byte
 * loader', and 'no buffer filler'.                                           */
{
    QUEX_NAME(Buffer)    new_buffer;

    if( QUEX_NAME(Buffer_has_intersection)(&me->buffer, Memory, (ptrdiff_t)MemorySize) ) {
        QUEX_NAME(error_code_set_if_first)(me, E_Error_ProvidedExternal_Memory_Intersects);
        goto ERROR_0;
    }
    else if( ! QUEX_NAME(BufferMemory_check_chunk)(Memory, MemorySize, EndOfFileP) ) {
        QUEX_NAME(error_code_set_if_first)(me, E_Error_ProvidedExternal_Memory_Corrupt);
        goto ERROR_0;
    }
    else if( me->error_code != E_Error_None ) {
        QUEX_NAME(error_code_set_if_first)(me, E_Error_IncludePush_OnError);
        goto ERROR_0;
    }

    /* The 'new_buffer' is only copied including the reference to the new 
     * memory. However, the box object 'new_buffer' is left alone.            */
    QUEX_NAME(Buffer_construct)(&new_buffer, 
                                (QUEX_NAME(LexatomLoader)*)0,
                                Memory, MemorySize, EndOfFileP,
                                E_Ownership_EXTERNAL,
                                (QUEX_NAME(Buffer)*)0);
    new_buffer.event = me->buffer.event;              /* Plain copy suffices. */

    if( ! QUEX_NAME(include_push_core)(me, InputName, &new_buffer,
                                       (QUEX_NAME(LexatomLoader)*)0) ) {
        goto ERROR_1;
    }
    return true;

    /* ERROR CASES: Free Resources ___________________________________________*/
ERROR_1:
    QUEX_NAME(Buffer_destruct)(&new_buffer);
ERROR_0:
    return false;
}

QUEX_INLINE bool
QUEX_NAME(include_push_core)(QUEX_TYPE_ANALYZER*       me,
                             const char*               InputNameP,
                             QUEX_NAME(Buffer)*        new_buffer,
                             QUEX_NAME(LexatomLoader)* new_filler)
{
    char*               new_input_name;
    QUEX_NAME(Memento)* memento;
    
    new_input_name = QUEXED(MemoryManager_clone_string)(InputNameP);
    if( ! new_input_name ) {
        QUEX_NAME(error_code_set_if_first)(me, E_Error_InputName_Set_Failed);
        goto ERROR_0;
    }

    memento = (QUEX_NAME(Memento)*)QUEXED(MemoryManager_allocate)(
                      sizeof(QUEX_NAME(Memento)), E_MemoryObjectType_MEMENTO);
    if( ! memento ) {
        goto ERROR_1;
    }
    else if( ! QUEX_NAME(Memento_construct)(memento, me, InputNameP) ) {
        goto ERROR_2;
    }
    else if( ! new_buffer ) {
        /* Buffer pointers are already copied into 'memento->buffer'.
         * Construct the new buffer directly into the current buffer.         */
        if( ! QUEX_NAME(Buffer_nested_construct)(&me->buffer, &memento->buffer, 
                                                 new_filler) ) {
            goto ERROR_3;
        }
    }
    else {
        QUEX_NAME(Buffer_shallow_copy)(&me->buffer, new_buffer);
    }

    __quex_assert(me->buffer._memory._front != memento->buffer._memory._front);
    QUEX_BUFFER_ASSERT_CONSISTENCY(&memento->buffer);
    QUEX_BUFFER_ASSERT_CONSISTENCY(&me->buffer);

    __QUEX_IF_COUNT((void)QUEX_NAME(Counter_construct)(&me->counter));
    me->__input_name    = new_input_name;
    me->_parent_memento = memento; 
    return true;
 
ERROR_3:
    QUEX_NAME(Buffer_shallow_copy)(&me->buffer, &memento->buffer);
ERROR_2:
    QUEXED(MemoryManager_free)(memento, E_MemoryObjectType_MEMENTO);
ERROR_1:
    QUEXED(MemoryManager_free)(new_input_name, E_MemoryObjectType_MEMENTO);
ERROR_0:
    return false;
}

QUEX_INLINE bool
QUEX_NAME(Memento_construct)(QUEX_NAME(Memento)* memento,
                             QUEX_TYPE_ANALYZER* me,
                             const char*         InputNameP)
{
    /* The 'buffer->_memory.including_buffer' must point to the buffer with
     * its address in the 'memento'. Thus, the including buffer must be copied
     * to the memento first.                                                  */
    QUEX_NAME(Buffer_shallow_copy)(&memento->buffer, &me->buffer);

#   ifndef __QUEX_OPTION_PLAIN_C
    /* Use placement 'new' for explicit call of constructor. 
     * Necessary in C++: Call to constructor for user defined members.        */
    new ((void*)memento) QUEX_NAME(Memento);
#   endif

    /* 'memento->__input_name' points to previously allocated memory.         */
    memento->__input_name              = me->__input_name;
    memento->_parent_memento           = me->_parent_memento;
    memento->__current_mode_p          = me->__current_mode_p; 
    memento->current_analyzer_function = me->current_analyzer_function;
#   if defined(QUEX_OPTION_ASSERTS)
    memento->DEBUG_analyzer_function_at_entry = me->DEBUG_analyzer_function_at_entry;
#   endif
    __QUEX_IF_COUNT(memento->counter   = me->counter); /* Plain copy is ok.   */ 
#   ifdef QUEX_OPTION_INDENTATION_TRIGGER
    memento->_indentation_handler_active_f = me->_indentation_handler_active_f;
#   endif

    /* Deriberately not subject to include handling:
     *    -- Mode stack.
     *    -- Token and token queues.
     *    -- Post categorizer.                                                */

    /* When 'user_memento_pack()' is called, nothing has been done to the 
     * current lexical analyzer object, yet!                                  */
    if( ! QUEX_NAME(user_memento_pack)(me, InputNameP, memento) ) {
        QUEX_NAME(error_code_set_if_first)(me, E_Error_UserMementoPack_Failed);
        return false;
    }
    return true;
}   

QUEX_INLINE bool
QUEX_NAME(include_pop)(QUEX_TYPE_ANALYZER* me)
/* RETURNS: true, if there was a memento that has been restored. 
 *          false, else.                                                     */
{
    QUEX_NAME(Memento)* memento;
    
    /* Not included? return 'false' to indicate we're on the top level       */
    if( ! me->_parent_memento ) {
        QUEX_NAME(error_code_set_if_first)(me, E_Error_IncludePopOnEmptyStack);
        return false;                             
    }

    memento = me->_parent_memento;
                                                                            
    /* Buffer_destruct() takes care of propper destructor calls for byte-
     * loaders, buffer fillers, and converters.                              */
    __quex_assert(me->buffer._memory._front != memento->buffer._memory._front);
    QUEX_NAME(Buffer_destruct)(&me->buffer);                              

    me->_parent_memento = memento->_parent_memento;
    /* memento_unpack():                                                    
     *    => Current mode                                                   
     *           => __current_mode_p                                        
     *              current_analyzer_function                                           
     *              DEBUG_analyzer_function_at_entry                                       
     *    => Line/Column Counters                                           
     *                                                                      
     * Unchanged by memento_unpack():                                       
     *    -- Mode stack                                                     
     *    -- Tokens and token queues.                                       
     *    -- Accumulator.                                                   
     *    -- Post categorizer.                                              
     *    -- File handle by constructor                                      */
                                                                            
    /* Copy Back of content that was stored upon inclusion.                  */

    if( me->__input_name ) {
        QUEXED(MemoryManager_free)(me->__input_name, E_MemoryObjectType_BUFFER_MEMORY);
    }
    /* 'memento->__input_name' points to previously allocated memory.        
     * 'me->__input_name' takes ownership again over allocated memory.       */
    me->__input_name                     = memento->__input_name;
    QUEX_NAME(Buffer_shallow_copy)(&me->buffer, &memento->buffer);

    me->__current_mode_p                 = memento->__current_mode_p; 
    me->current_analyzer_function        = memento->current_analyzer_function;
#   if defined(QUEX_OPTION_ASSERTS)
    me->DEBUG_analyzer_function_at_entry = memento->DEBUG_analyzer_function_at_entry;
#   endif
    __QUEX_IF_COUNT(me->counter          = memento->counter);
#   ifdef QUEX_OPTION_INDENTATION_TRIGGER
    me->_indentation_handler_active_f    = memento->_indentation_handler_active_f;
#   endif

    QUEX_NAME(user_memento_unpack)(me, memento);

#   ifndef __QUEX_OPTION_PLAIN_C
    /* Counterpart to placement new: Explicit destructor call.
     * Necessary in C++: Trigger call to destructor for user defined members.*/
    memento->~QUEX_NAME(Memento_tag)();
#   endif

    QUEXED(MemoryManager_free)((void*)memento, E_MemoryObjectType_MEMENTO); 

    /* Return to including file succesful                                    */
    return true;
}
     
QUEX_INLINE void
QUEX_NAME(include_stack_delete)(QUEX_TYPE_ANALYZER* me)
{
    /* Avoid 'E_Error_IncludePopOnEmptyStack'. Check before.                 */
    if( ! me->_parent_memento ) return;
    while( QUEX_NAME(include_pop)(me) );
}

QUEX_INLINE bool
QUEX_NAME(include_detect_recursion)(QUEX_TYPE_ANALYZER* me,
                                    const char*         InputName)
{
    QUEX_NAME(Memento)* iterator;
    for(iterator = me->_parent_memento; iterator ; 
        iterator = iterator->_parent_memento ) {
        if( __QUEX_STD_strcmp(iterator->__input_name, InputName) == 0 ) {
            return true;
        }
    }
    return false;
}

QUEX_NAMESPACE_MAIN_CLOSE

#endif /*  __QUEX_INCLUDE_GUARD__ANALYZER__STRUCT__INCLUDE_STACK_I */
