const merge = require('lodash/merge');
const actionTypes = require('../actions/actionTypes');
const initialState = {
  error: false,
  selected: null
};

module.exports = function(state, action) {
  if (typeof state === 'undefined') {
    state = initialState;
  }

  switch (action.type) {
    case actionTypes.ADD_SELECTED_MESSAGE:
      return Object.assign({}, state, {
        selected: Object.assign({}, state.selected, {
          messages: state.selected.messages.concat(action.payload.message)
        })
      });
    case actionTypes.CLEAR_SELECTED:
      return Object.assign({}, state, { selected: null });
    case actionTypes.REMOVE_SELECTED_MESSAGE: {
      const filteredMessages = state.selected.messages.filter(message => message.id !== action.payload.id);
      return Object.assign({}, state, {
        selected: Object.assign({}, state.selected, { messages: filteredMessages })
      });
    }
    case actionTypes.SET_MESSAGES_ERROR:
      return Object.assign({}, state, { error: action.payload.error });
    case actionTypes.SET_SELECTED_MESSAGE:
      return Object.assign({}, state, { selected: action.payload.selected });
    case actionTypes.UPDATE_SELECTED_MESSAGE:
      return Object.assign({}, state, {
        selected: merge({}, state.selected, action.payload.selected)
      });
    case actionTypes.SET_CONVERSATIONS:
      return Object.assign({}, state, { conversations: action.payload.conversations });
    case actionTypes.MARK_SELECTED_CONVERSATION_READ: {
      if (!state.conversations || !state.selected.messages) {
        return state;
      }
      const ids = state.selected.messages.map(message => message.doc._id);
      const updated = state.conversations.map(conversation => {
        if (ids.includes(conversation.id)) {
          conversation = Object.assign({}, conversation, { read: true });
        }
        return conversation;
      });
      return Object.assign({}, state, { conversations: updated });
    }
    default:
      return state;
  }
};
