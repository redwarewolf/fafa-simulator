using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class TabGroup : MonoBehaviour
{

    public GameObject defaultPanel;
    private GameObject currentPanel;

    void Awake()
    {
        defaultPanel.SetActive(true);
        currentPanel = defaultPanel;
    }

    public void activatePanel(GameObject panel)
    {
        currentPanel.SetActive(false);
        currentPanel = panel;
        currentPanel.SetActive(true);
    }
}
