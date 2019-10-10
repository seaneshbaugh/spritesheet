import React, { Component } from "react";

class ToggleSwitch extends Component {
  render() {
    return (
      <div className="switch">
        <label>
          {this.props.offText}
          <input type="checkbox" onClick={this.props.onClick}></input>
          <span className="lever"></span>
          {this.props.onText}
        </label>
      </div>
    );
  }
}

export default ToggleSwitch;
