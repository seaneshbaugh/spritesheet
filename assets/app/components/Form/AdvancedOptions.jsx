import React, { Component } from "react";

class AdvancedOptions extends Component {
  render() {
    return (
      <div className="advanced-options">
        <input name="options[class]" type="text" placeholder="CSS Class Name"/>
        <input name="options[prefix]" type="text" placeholder="CSS Class Prefix"/>
        <input name="options[columns]" type="text" placeholder="Number of Columns"/>
      </div>
    );
  }
}

export default AdvancedOptions;
